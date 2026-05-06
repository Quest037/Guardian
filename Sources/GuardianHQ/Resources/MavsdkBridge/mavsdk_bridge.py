#!/usr/bin/env python3
"""
Guardian MAVSDK sidecar: gRPC to an already-running mavsdk_server; JSON lines on stdout.

Usage: python3 mavsdk_bridge.py [host] [port] [connect_url] [system_ids_csv]
Env:
  GUARDIAN_MAVSDK_GRPC_HOST, GUARDIAN_MAVSDK_GRPC_PORT (defaults 127.0.0.1:50051)
  GUARDIAN_MAVSDK_CONNECT_URL (optional MAVLink URL passed to System.connect)
  GUARDIAN_MAVSDK_MAX_SYSTEMS (default 32)
  GUARDIAN_MAVSDK_SYSTEM_IDS (optional CSV list of MAVLink system IDs, e.g. "1,2,7")
"""

from __future__ import annotations

import asyncio
import inspect
import json
import math
import os
import sys
import traceback

MAX_SYSTEMS_DEFAULT = 32


def _emit(obj: dict) -> None:
    print(json.dumps(obj, separators=(",", ":"), allow_nan=False), flush=True)


def _emit_vehicle(vehicle_id: str, system_id: int, obj: dict) -> None:
    payload = dict(obj)
    payload["vehicle_id"] = vehicle_id
    payload["system_id"] = system_id
    _emit(payload)


def _err(msg: str) -> None:
    print(msg, file=sys.stderr, flush=True)


def _f(v):
    """JSON-safe float: drop NaN/inf so Swift JSONDecoder accepts the line."""
    if v is None:
        return None
    try:
        x = float(v)
    except (TypeError, ValueError):
        return None
    if not math.isfinite(x):
        return None
    return x


def _i(v):
    if v is None:
        return None
    try:
        return int(v)
    except (TypeError, ValueError):
        return None


def _parse_system_ids_csv(raw: str | None) -> list[int]:
    if raw is None:
        return []
    parts = [p.strip() for p in str(raw).split(",")]
    ids = []
    for p in parts:
        if not p:
            continue
        val = _i(p)
        if val is None:
            continue
        if 1 <= val <= 255:
            ids.append(val)
    return sorted(set(ids))


async def _stdin_command_loop(queue: asyncio.Queue[dict]) -> None:
    reader = asyncio.StreamReader()
    protocol = asyncio.StreamReaderProtocol(reader)
    loop = asyncio.get_running_loop()
    await loop.connect_read_pipe(lambda: protocol, sys.stdin)
    while True:
        line = await reader.readline()
        if not line:
            await asyncio.sleep(0.2)
            continue
        text = line.decode("utf-8", errors="ignore").strip()
        if not text:
            continue
        try:
            cmd = json.loads(text)
        except Exception:
            _emit({"type": "bridge_error", "message": "bad_command_json"})
            continue
        if isinstance(cmd, dict):
            await queue.put(cmd)


async def _run_system(host: str, port: int, system_id: int, connect_url: str | None) -> None:
    from mavsdk import System

    vehicle_id = f"sysid:{system_id}"
    # MAVSDK-Python constructor kwargs vary across major versions.
    try:
        sig = inspect.signature(System)
        params = set(sig.parameters.keys())
    except Exception:
        params = set()

    ctor_kwargs = {}
    if "mavsdk_server_address" in params:
        ctor_kwargs["mavsdk_server_address"] = host
    if "port" in params:
        ctor_kwargs["port"] = port
    if "sysid" in params:
        ctor_kwargs["sysid"] = system_id
    elif "system_id" in params:
        ctor_kwargs["system_id"] = system_id
    else:
        _emit_vehicle(
            vehicle_id,
            system_id,
            {"type": "bridge_error", "message": "system_selector_unavailable:python_mavsdk_ctor_has_no_sysid"},
        )

    try:
        drone = System(**ctor_kwargs)
    except asyncio.CancelledError:
        raise
    except Exception as e:
        _emit_vehicle(vehicle_id, system_id, {"type": "bridge_error", "message": f"system_ctor:{e}"})
        return

    async def wait_connected(timeout_s: float = 30.0) -> bool:
        async def _wait() -> bool:
            async for state in drone.core.connection_state():
                if bool(getattr(state, "is_connected", False)):
                    return True
            return False

        try:
            return await asyncio.wait_for(_wait(), timeout=timeout_s)
        except asyncio.TimeoutError:
            return False
        except Exception as e:
            _emit_vehicle(vehicle_id, system_id, {"type": "bridge_error", "message": f"connection_state:{e}"})
            return False

    async def detect_and_emit_vehicle_stack() -> None:
        stack = "unknown"
        try:
            iden = await asyncio.wait_for(drone.info.get_identification(), timeout=10.0)
            vendor = (getattr(iden, "vendor_name", None) or "").lower()
            product = (getattr(iden, "product_name", None) or "").lower()
            blob = f"{vendor} {product}"
            if any(k in blob for k in ("ardupilot", "arducopter", "arduplane", "ardurover", "ardusub", "arduboat", "apm")):
                stack = "ardupilot"
            elif "px4" in blob or "pixhawk" in blob:
                stack = "px4"
        except Exception:
            pass
        if stack == "unknown":
            try:
                prod = await asyncio.wait_for(drone.info.get_product(), timeout=4.0)
                vendor = (getattr(prod, "vendor_name", None) or "").lower()
                product = (getattr(prod, "product_name", None) or "").lower()
                blob = f"{vendor} {product}"
                if any(k in blob for k in ("ardupilot", "arducopter", "arduplane", "ardurover", "ardusub", "arduboat", "apm")):
                    stack = "ardupilot"
                elif "px4" in blob or "pixhawk" in blob:
                    stack = "px4"
            except Exception:
                pass
        _emit_vehicle(vehicle_id, system_id, {"type": "vehicle_stack", "stack": stack})

    async def detect_and_emit_version() -> None:
        try:
            ver = await asyncio.wait_for(drone.info.get_version(), timeout=12.0)
            _emit_vehicle(
                vehicle_id,
                system_id,
                {
                    "type": "vehicle_version",
                    "flight_sw_major": _i(getattr(ver, "flight_sw_major", None)),
                    "flight_sw_minor": _i(getattr(ver, "flight_sw_minor", None)),
                    "flight_sw_patch": _i(getattr(ver, "flight_sw_patch", None)),
                    "flight_sw_git_hash": getattr(ver, "flight_sw_git_hash", None) or None,
                    "os_sw_git_hash": getattr(ver, "os_sw_git_hash", None) or None,
                    "flight_sw_version_type": str(getattr(ver, "flight_sw_version_type", "") or ""),
                },
            )
        except Exception:
            pass

    def _watch(name: str, subscribe_coro_factory):
        async def _inner() -> None:
            try:
                stream = subscribe_coro_factory() if callable(subscribe_coro_factory) else subscribe_coro_factory
                async for sample in stream:
                    try:
                        await _dispatch_sample(name, sample)
                    except Exception as e:
                        _emit_vehicle(vehicle_id, system_id, {"type": "bridge_error", "message": f"{name}_emit:{e}"})
            except asyncio.CancelledError:
                raise
            except Exception as e:
                _emit_vehicle(vehicle_id, system_id, {"type": "bridge_error", "message": f"{name}_stream:{e}"})

        return _inner()

    async def _dispatch_sample(kind: str, sample) -> None:
        if kind == "armed":
            _emit_vehicle(vehicle_id, system_id, {"type": "armed", "armed": bool(sample)})
            return
        if kind == "flight_mode":
            _emit_vehicle(vehicle_id, system_id, {"type": "flight_mode", "flight_mode": str(sample)})
            return
        if kind == "position":
            _emit_vehicle(
                vehicle_id,
                system_id,
                {
                    "type": "position",
                    "lat_deg": _f(sample.latitude_deg),
                    "lon_deg": _f(sample.longitude_deg),
                    "rel_alt_m": _f(sample.relative_altitude_m),
                    "abs_alt_m": _f(sample.absolute_altitude_m),
                },
            )
            return
        if kind == "battery":
            _emit_vehicle(
                vehicle_id,
                system_id,
                {
                    "type": "battery",
                    "battery_id": _i(getattr(sample, "id", None)),
                    "battery_temp_degc": _f(getattr(sample, "temperature_degc", None)),
                    "battery_voltage_v": _f(sample.voltage_v),
                    "battery_current_a": _f(sample.current_battery_a),
                    "battery_capacity_consumed_ah": _f(sample.capacity_consumed_ah),
                    "battery_remaining_pct": _f(sample.remaining_percent),
                    "battery_time_remaining_s": _f(sample.time_remaining_s),
                },
            )
            return
        if kind == "gps_info":
            fix = getattr(sample, "fix_type", None)
            _emit_vehicle(
                vehicle_id,
                system_id,
                {
                    "type": "gps_info",
                    "gps_num_satellites": _i(sample.num_satellites),
                    "gps_fix_type": str(fix) if fix is not None else None,
                },
            )
            return
        if kind == "health":
            _emit_vehicle(
                vehicle_id,
                system_id,
                {
                    "type": "health",
                    "health_gyrometer_calibration_ok": sample.is_gyrometer_calibration_ok,
                    "health_accelerometer_calibration_ok": sample.is_accelerometer_calibration_ok,
                    "health_magnetometer_calibration_ok": sample.is_magnetometer_calibration_ok,
                    "health_local_position_ok": sample.is_local_position_ok,
                    "health_global_position_ok": sample.is_global_position_ok,
                    "health_home_position_ok": sample.is_home_position_ok,
                    "health_armable": sample.is_armable,
                },
            )
            return
        if kind == "health_all_ok":
            _emit_vehicle(vehicle_id, system_id, {"type": "health_all_ok", "health_all_ok": bool(sample)})
            return
        if kind == "in_air":
            _emit_vehicle(vehicle_id, system_id, {"type": "in_air", "in_air": bool(sample)})
            return
        if kind == "landed_state":
            _emit_vehicle(vehicle_id, system_id, {"type": "landed_state", "landed_state": str(sample)})
            return
        if kind == "rc_status":
            _emit_vehicle(
                vehicle_id,
                system_id,
                {
                    "type": "rc_status",
                    "rc_was_available_once": sample.was_available_once,
                    "rc_is_available": sample.is_available,
                    "rc_signal_strength_pct": _f(sample.signal_strength_percent),
                },
            )
            return
        if kind == "attitude_euler":
            _emit_vehicle(
                vehicle_id,
                system_id,
                {
                    "type": "attitude_euler",
                    "roll_deg": _f(sample.roll_deg),
                    "pitch_deg": _f(sample.pitch_deg),
                    "yaw_deg": _f(sample.yaw_deg),
                    "attitude_timestamp_us": _i(getattr(sample, "timestamp_us", None)),
                },
            )
            return
        if kind == "attitude_quaternion":
            _emit_vehicle(
                vehicle_id,
                system_id,
                {
                    "type": "attitude_quaternion",
                    "quat_w": _f(sample.w),
                    "quat_x": _f(sample.x),
                    "quat_y": _f(sample.y),
                    "quat_z": _f(sample.z),
                    "quat_timestamp_us": _i(getattr(sample, "timestamp_us", None)),
                },
            )
            return
        if kind == "attitude_angular_velocity_body":
            _emit_vehicle(
                vehicle_id,
                system_id,
                {
                    "type": "attitude_angular_velocity_body",
                    "ang_vel_roll_rad_s": _f(sample.roll_rad_s),
                    "ang_vel_pitch_rad_s": _f(sample.pitch_rad_s),
                    "ang_vel_yaw_rad_s": _f(sample.yaw_rad_s),
                },
            )
            return
        if kind == "velocity_ned":
            _emit_vehicle(
                vehicle_id,
                system_id,
                {"type": "velocity_ned", "north_m_s": _f(sample.north_m_s), "east_m_s": _f(sample.east_m_s), "down_m_s": _f(sample.down_m_s)},
            )
            return
        if kind == "altitude":
            _emit_vehicle(
                vehicle_id,
                system_id,
                {
                    "type": "altitude",
                    "alt_monotonic_m": _f(sample.altitude_monotonic_m),
                    "alt_amsl_m": _f(sample.altitude_amsl_m),
                    "alt_local_m": _f(sample.altitude_local_m),
                    "alt_relative_m": _f(sample.altitude_relative_m),
                    "alt_terrain_m": _f(sample.altitude_terrain_m),
                    "alt_bottom_clearance_m": _f(sample.bottom_clearance_m),
                },
            )
            return
        if kind == "home":
            _emit_vehicle(
                vehicle_id,
                system_id,
                {
                    "type": "home",
                    "home_lat_deg": _f(sample.latitude_deg),
                    "home_lon_deg": _f(sample.longitude_deg),
                    "home_abs_alt_m": _f(sample.absolute_altitude_m),
                    "home_rel_alt_m": _f(sample.relative_altitude_m),
                },
            )
            return
        if kind == "status_text":
            stype = getattr(sample, "type", None)
            _emit_vehicle(
                vehicle_id,
                system_id,
                {"type": "status_text", "status_severity": str(stype) if stype is not None else None, "status_text": getattr(sample, "text", None)},
            )
            return
        if kind == "position_velocity_ned":
            pos = sample.position
            vel = sample.velocity
            _emit_vehicle(
                vehicle_id,
                system_id,
                {
                    "type": "position_velocity_ned",
                    "pos_vel_north_m": _f(pos.north_m),
                    "pos_vel_east_m": _f(pos.east_m),
                    "pos_vel_down_m": _f(pos.down_m),
                    "pos_vel_vn_m_s": _f(vel.north_m_s),
                    "pos_vel_ve_m_s": _f(vel.east_m_s),
                    "pos_vel_vd_m_s": _f(vel.down_m_s),
                },
            )
            return
        if kind == "heading":
            _emit_vehicle(vehicle_id, system_id, {"type": "heading", "heading_deg": _f(sample.heading_deg)})
            return
        if kind == "distance_sensor":
            ori = sample.orientation
            _emit_vehicle(
                vehicle_id,
                system_id,
                {
                    "type": "distance_sensor",
                    "dist_min_m": _f(sample.minimum_distance_m),
                    "dist_max_m": _f(sample.maximum_distance_m),
                    "dist_cur_m": _f(sample.current_distance_m),
                    "dist_orient_roll_deg": _f(getattr(ori, "roll_deg", None)),
                    "dist_orient_pitch_deg": _f(getattr(ori, "pitch_deg", None)),
                    "dist_orient_yaw_deg": _f(getattr(ori, "yaw_deg", None)),
                },
            )
            return
        if kind == "wind":
            _emit_vehicle(
                vehicle_id,
                system_id,
                {"type": "wind", "wind_x_ned_m_s": _f(sample.wind_x_ned_m_s), "wind_y_ned_m_s": _f(sample.wind_y_ned_m_s), "wind_z_ned_m_s": _f(sample.wind_z_ned_m_s)},
            )
            return
        if kind == "imu":
            a = sample.acceleration_frd
            g = sample.angular_velocity_frd
            m = sample.magnetic_field_frd
            _emit_vehicle(
                vehicle_id,
                system_id,
                {
                    "type": "imu",
                    "imu_acc_fwd": _f(a.forward_m_s2),
                    "imu_acc_right": _f(a.right_m_s2),
                    "imu_acc_down": _f(a.down_m_s2),
                    "imu_gyro_fwd": _f(g.forward_rad_s),
                    "imu_gyro_right": _f(g.right_rad_s),
                    "imu_gyro_down": _f(g.down_rad_s),
                    "imu_mag_fwd": _f(m.forward_gauss),
                    "imu_mag_right": _f(m.right_gauss),
                    "imu_mag_down": _f(m.down_gauss),
                    "imu_temp_degc": _f(sample.temperature_degc),
                    "imu_timestamp_us": _i(sample.timestamp_us),
                },
            )
            return
        if kind == "scaled_pressure":
            _emit_vehicle(
                vehicle_id,
                system_id,
                {"type": "scaled_pressure", "press_abs_hpa": _f(sample.absolute_pressure_hpa), "press_diff_hpa": _f(sample.differential_pressure_hpa), "press_temp_degc": _f(sample.temperature_deg)},
            )
            return
        if kind == "fixedwing_metrics":
            _emit_vehicle(
                vehicle_id,
                system_id,
                {
                    "type": "fixedwing_metrics",
                    "fw_airspeed_m_s": _f(sample.airspeed_m_s),
                    "fw_throttle_pct": _f(sample.throttle_percentage),
                    "fw_climb_m_s": _f(sample.climb_rate_m_s),
                    "fw_gspeed_m_s": _f(sample.groundspeed_m_s),
                    "fw_heading_deg": _f(sample.heading_deg),
                    "fw_abs_alt_m": _f(sample.absolute_altitude_m),
                },
            )
            return
        if kind == "vtol_state":
            _emit_vehicle(vehicle_id, system_id, {"type": "vtol_state", "vtol_state": str(sample)})
            return
        if kind == "odometry":
            q = sample.q
            pb = sample.position_body
            vb = sample.velocity_body
            _emit_vehicle(
                vehicle_id,
                system_id,
                {
                    "type": "odometry",
                    "odom_usec": _i(sample.time_usec),
                    "odom_frame": str(sample.frame_id),
                    "odom_child_frame": str(sample.child_frame_id),
                    "odom_px": _f(pb.x_m),
                    "odom_py": _f(pb.y_m),
                    "odom_pz": _f(pb.z_m),
                    "odom_qw": _f(q.w),
                    "odom_qx": _f(q.x),
                    "odom_qy": _f(q.y),
                    "odom_qz": _f(q.z),
                    "odom_vx": _f(vb.x_m_s),
                    "odom_vy": _f(vb.y_m_s),
                    "odom_vz": _f(vb.z_m_s),
                },
            )
            return
        if kind == "raw_gps":
            _emit_vehicle(
                vehicle_id,
                system_id,
                {
                    "type": "raw_gps",
                    "raw_gps_timestamp_us": _i(sample.timestamp_us),
                    "raw_gps_lat_deg": _f(sample.latitude_deg),
                    "raw_gps_lon_deg": _f(sample.longitude_deg),
                    "raw_gps_abs_alt_m": _f(sample.absolute_altitude_m),
                    "raw_gps_hdop": _f(sample.hdop),
                    "raw_gps_vdop": _f(sample.vdop),
                    "raw_gps_vel_m_s": _f(sample.velocity_m_s),
                    "raw_gps_cog_deg": _f(sample.cog_deg),
                    "raw_gps_alt_ellipsoid_m": _f(sample.altitude_ellipsoid_m),
                    "raw_gps_horiz_unc_m": _f(sample.horizontal_uncertainty_m),
                    "raw_gps_vert_unc_m": _f(sample.vertical_uncertainty_m),
                    "raw_gps_vel_unc_m_s": _f(sample.velocity_uncertainty_m_s),
                    "raw_gps_hdg_unc_deg": _f(sample.heading_uncertainty_deg),
                    "raw_gps_yaw_deg": _f(sample.yaw_deg),
                },
            )
            return
        if kind == "unix_epoch_time":
            _emit_vehicle(vehicle_id, system_id, {"type": "unix_epoch_time", "unix_epoch_us": _i(sample)})
            return

    watch_specs = [
        ("armed", "armed"),
        ("flight_mode", "flight_mode"),
        ("position", "position"),
        ("battery", "battery"),
        ("gps_info", "gps_info"),
        ("health", "health"),
        ("health_all_ok", "health_all_ok"),
        ("in_air", "in_air"),
        ("landed_state", "landed_state"),
        ("rc_status", "rc_status"),
        ("attitude_euler", "attitude_euler"),
        ("attitude_quaternion", "attitude_quaternion"),
        ("attitude_angular_velocity_body", "attitude_angular_velocity_body"),
        ("velocity_ned", "velocity_ned"),
        ("altitude", "altitude"),
        ("home", "home"),
        ("status_text", "status_text"),
        ("position_velocity_ned", "position_velocity_ned"),
        ("heading", "heading"),
        ("distance_sensor", "distance_sensor"),
        ("wind", "wind"),
        ("imu", "imu"),
        ("scaled_pressure", "scaled_pressure"),
        ("fixedwing_metrics", "fixedwing_metrics"),
        ("vtol_state", "vtol_state"),
        ("odometry", "odometry"),
        ("raw_gps", "raw_gps"),
        ("unix_epoch_time", "unix_epoch_time"),
    ]

    while True:
        try:
            # We connect to an already running mavsdk_server (host/port provided in ctor),
            # so this call should only initialize the gRPC client/plugins. Passing
            # system_address here can attempt to (re)configure links at the Python client
            # layer and has caused false timeouts in practice.
            await asyncio.wait_for(drone.connect(), timeout=20.0)
        except asyncio.TimeoutError:
            _emit_vehicle(
                vehicle_id,
                system_id,
                {
                    "type": "bridge_error",
                    "message": "connect_rpc_timeout:mavsdk_connect_call_did_not_complete;transport_may_still_be_live",
                },
            )
            await asyncio.sleep(1.0)
            continue
        except asyncio.CancelledError:
            raise
        except Exception as e:
            _emit_vehicle(vehicle_id, system_id, {"type": "bridge_error", "message": f"connect:{e}"})
            await asyncio.sleep(1.0)
            continue

        if not await wait_connected():
            _emit_vehicle(vehicle_id, system_id, {"type": "bridge_error", "message": "connect_timeout:no_vehicle_discovered"})
            await asyncio.sleep(1.0)
            continue

        _emit_vehicle(vehicle_id, system_id, {"type": "bridge_ready", "host": host, "port": port})
        asyncio.create_task(detect_and_emit_vehicle_stack())
        asyncio.create_task(detect_and_emit_version())

        watchers = []
        for kind, attr_name in watch_specs:
            subscribe = getattr(drone.telemetry, attr_name, None)
            if subscribe is None:
                _emit_vehicle(vehicle_id, system_id, {"type": "bridge_error", "message": f"missing_stream:{kind}"})
                continue
            watchers.append(_watch(kind, subscribe))

        if not watchers:
            _emit_vehicle(vehicle_id, system_id, {"type": "bridge_error", "message": "no_supported_streams"})
            await asyncio.sleep(1.0)
            continue

        try:
            await asyncio.gather(*watchers)
        except asyncio.CancelledError:
            raise
        except Exception as e:
            _emit_vehicle(vehicle_id, system_id, {"type": "bridge_error", "message": f"watchers:{e}"})
            await asyncio.sleep(1.0)


async def _run(host: str, port: int, connect_url: str | None, system_ids: list[int]) -> None:
    try:
        from mavsdk import System  # noqa: F401
    except ImportError:
        _err(
            "mavsdk Python package not found. Run: pip3 install -r requirements.txt "
            "(in this directory) or: make bridge-deps"
        )
        _emit({"type": "bridge_error", "message": "missing_mavsdk_python_package"})
        sys.exit(1)

    boot = {"type": "bridge_listening", "host": host, "port": port}
    if connect_url:
        boot["connect_url"] = connect_url
    if system_ids:
        boot["system_ids"] = system_ids
    _emit(boot)

    desired_ids = set(system_ids)
    if not desired_ids:
        default_max = _i(os.environ.get("GUARDIAN_MAVSDK_MAX_SYSTEMS"))
        if default_max:
            default_max = max(1, min(default_max, 255))
            desired_ids = set(range(1, default_max + 1))

    command_queue: asyncio.Queue[dict] = asyncio.Queue()
    command_task = asyncio.create_task(_stdin_command_loop(command_queue))
    workers: dict[int, asyncio.Task] = {}

    def _start_worker(sid: int) -> None:
        if sid in workers and not workers[sid].done():
            return
        workers[sid] = asyncio.create_task(_run_system(host, port, sid, connect_url))

    async def _reconcile() -> None:
        # Remove workers no longer desired.
        for sid in list(workers.keys()):
            if sid not in desired_ids:
                workers[sid].cancel()
                del workers[sid]
        # Ensure desired workers exist.
        for sid in sorted(desired_ids):
            _start_worker(sid)

    await _reconcile()

    try:
        while True:
            # Surface worker crashes and recreate while still desired.
            for sid, task in list(workers.items()):
                if not task.done():
                    continue
                del workers[sid]
                try:
                    result = task.result()
                    if isinstance(result, asyncio.CancelledError):
                        raise result
                except asyncio.CancelledError:
                    raise
                except Exception as e:
                    _emit({"type": "bridge_error", "message": f"system_task_exception:sysid:{sid}:{e}"})
                if sid in desired_ids:
                    _start_worker(sid)

            try:
                cmd = await asyncio.wait_for(command_queue.get(), timeout=0.5)
            except asyncio.TimeoutError:
                continue

            ctype = str(cmd.get("type", "")).strip().lower()
            if ctype == "set_system_ids":
                ids_raw = cmd.get("system_ids", [])
                if isinstance(ids_raw, list):
                    parsed = []
                    for item in ids_raw:
                        val = _i(item)
                        if val is not None and 1 <= val <= 255:
                            parsed.append(val)
                    desired_ids = set(parsed)
                    _emit({"type": "bridge_system_ids_updated", "system_ids": sorted(desired_ids)})
                    await _reconcile()
            elif ctype:
                _emit({"type": "bridge_error", "message": f"unknown_command:{ctype}"})
    finally:
        command_task.cancel()
        for t in workers.values():
            t.cancel()


def main() -> None:
    host = os.environ.get("GUARDIAN_MAVSDK_GRPC_HOST", "127.0.0.1")
    port_s = os.environ.get("GUARDIAN_MAVSDK_GRPC_PORT", "50051")
    connect_url = os.environ.get("GUARDIAN_MAVSDK_CONNECT_URL")
    system_ids_csv = os.environ.get("GUARDIAN_MAVSDK_SYSTEM_IDS")
    if len(sys.argv) >= 2:
        host = sys.argv[1]
    if len(sys.argv) >= 3:
        port_s = sys.argv[2]
    if len(sys.argv) >= 4:
        connect_url = sys.argv[3]
    if len(sys.argv) >= 5:
        system_ids_csv = sys.argv[4]
    if connect_url is not None:
        connect_url = connect_url.strip() or None
    system_ids = _parse_system_ids_csv(system_ids_csv)
    try:
        port = int(port_s)
    except ValueError:
        _emit({"type": "bridge_error", "message": f"bad_port:{port_s}"})
        sys.exit(1)

    try:
        asyncio.run(_run(host, port, connect_url, system_ids))
    except KeyboardInterrupt:
        pass
    except Exception as e:
        _err(f"bridge runtime failed: {e}\n{traceback.format_exc()}")
        _emit({"type": "bridge_error", "message": f"runtime:{e}"})


if __name__ == "__main__":
    main()

