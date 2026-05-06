#!/usr/bin/env python3
"""
Guardian MAVSDK sidecar: gRPC to an already-running mavsdk_server; JSON lines on stdout.

Usage: python3 mavsdk_bridge.py [host] [port]
Env: GUARDIAN_MAVSDK_GRPC_HOST, GUARDIAN_MAVSDK_GRPC_PORT (defaults 127.0.0.1:50051)
"""

from __future__ import annotations

import asyncio
import json
import math
import os
import sys
import traceback


def _emit(obj: dict) -> None:
    print(json.dumps(obj, separators=(",", ":"), allow_nan=False), flush=True)


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


async def _run(host: str, port: int) -> None:
    try:
        from mavsdk import System
    except ImportError:
        _err(
            "mavsdk Python package not found. Run: pip3 install -r requirements.txt "
            "(in this directory) or: make bridge-deps"
        )
        _emit({"type": "bridge_error", "message": "missing_mavsdk_python_package"})
        sys.exit(1)

    drone = System(mavsdk_server_address=host, port=port)
    _emit({"type": "bridge_listening", "host": host, "port": port})
    try:
        await drone.connect()
    except Exception as e:
        _err(f"connect failed: {e}\n{traceback.format_exc()}")
        _emit({"type": "bridge_error", "message": str(e)})
        sys.exit(2)

    _emit({"type": "bridge_ready", "host": host, "port": port})

    async def detect_and_emit_vehicle_stack() -> None:
        stack = "unknown"
        try:
            iden = await asyncio.wait_for(drone.info.get_identification(), timeout=10.0)
            vendor = (getattr(iden, "vendor_name", None) or "").lower()
            product = (getattr(iden, "product_name", None) or "").lower()
            blob = f"{vendor} {product}"
            if any(
                k in blob
                for k in (
                    "ardupilot",
                    "arducopter",
                    "arduplane",
                    "ardurover",
                    "ardusub",
                    "arduboat",
                    "apm",
                )
            ):
                stack = "ardupilot"
            elif "px4" in blob or "pixhawk" in blob:
                stack = "px4"
        except asyncio.TimeoutError:
            pass
        except Exception:
            pass
        if stack == "unknown":
            try:
                prod = await asyncio.wait_for(drone.info.get_product(), timeout=4.0)
                vendor = (getattr(prod, "vendor_name", None) or "").lower()
                product = (getattr(prod, "product_name", None) or "").lower()
                blob = f"{vendor} {product}"
                if any(
                    k in blob
                    for k in (
                        "ardupilot",
                        "arducopter",
                        "arduplane",
                        "ardurover",
                        "ardusub",
                        "arduboat",
                        "apm",
                    )
                ):
                    stack = "ardupilot"
                elif "px4" in blob or "pixhawk" in blob:
                    stack = "px4"
            except Exception:
                pass
        _emit({"type": "vehicle_stack", "stack": stack})

    async def detect_and_emit_version() -> None:
        try:
            ver = await asyncio.wait_for(drone.info.get_version(), timeout=12.0)
            _emit(
                {
                    "type": "vehicle_version",
                    "flight_sw_major": _i(getattr(ver, "flight_sw_major", None)),
                    "flight_sw_minor": _i(getattr(ver, "flight_sw_minor", None)),
                    "flight_sw_patch": _i(getattr(ver, "flight_sw_patch", None)),
                    "flight_sw_git_hash": getattr(ver, "flight_sw_git_hash", None) or None,
                    "os_sw_git_hash": getattr(ver, "os_sw_git_hash", None) or None,
                    "flight_sw_version_type": str(
                        getattr(ver, "flight_sw_version_type", "") or ""
                    ),
                }
            )
        except Exception:
            pass

    asyncio.create_task(detect_and_emit_vehicle_stack())
    asyncio.create_task(detect_and_emit_version())

    def _watch(name: str, subscribe_coro_factory):
        async def _inner() -> None:
            try:
                async for sample in subscribe_coro_factory():
                    try:
                        await _dispatch_sample(name, sample)
                    except Exception as e:
                        _emit({"type": "bridge_error", "message": f"{name}_emit:{e}"})
            except asyncio.CancelledError:
                raise
            except Exception as e:
                _emit({"type": "bridge_error", "message": f"{name}_stream:{e}"})

        return _inner()

    async def _dispatch_sample(kind: str, sample) -> None:
        if kind == "armed":
            _emit({"type": "armed", "armed": bool(sample)})
            return
        if kind == "flight_mode":
            _emit({"type": "flight_mode", "flight_mode": str(sample)})
            return
        if kind == "position":
            _emit(
                {
                    "type": "position",
                    "lat_deg": _f(sample.latitude_deg),
                    "lon_deg": _f(sample.longitude_deg),
                    "rel_alt_m": _f(sample.relative_altitude_m),
                    "abs_alt_m": _f(sample.absolute_altitude_m),
                }
            )
            return
        if kind == "battery":
            _emit(
                {
                    "type": "battery",
                    "battery_id": _i(getattr(sample, "id", None)),
                    "battery_temp_degc": _f(getattr(sample, "temperature_degc", None)),
                    "battery_voltage_v": _f(sample.voltage_v),
                    "battery_current_a": _f(sample.current_battery_a),
                    "battery_capacity_consumed_ah": _f(sample.capacity_consumed_ah),
                    "battery_remaining_pct": _f(sample.remaining_percent),
                    "battery_time_remaining_s": _f(sample.time_remaining_s),
                }
            )
            return
        if kind == "gps_info":
            fix = getattr(sample, "fix_type", None)
            _emit(
                {
                    "type": "gps_info",
                    "gps_num_satellites": _i(sample.num_satellites),
                    "gps_fix_type": str(fix) if fix is not None else None,
                }
            )
            return
        if kind == "health":
            _emit(
                {
                    "type": "health",
                    "health_gyrometer_calibration_ok": sample.is_gyrometer_calibration_ok,
                    "health_accelerometer_calibration_ok": sample.is_accelerometer_calibration_ok,
                    "health_magnetometer_calibration_ok": sample.is_magnetometer_calibration_ok,
                    "health_local_position_ok": sample.is_local_position_ok,
                    "health_global_position_ok": sample.is_global_position_ok,
                    "health_home_position_ok": sample.is_home_position_ok,
                    "health_armable": sample.is_armable,
                }
            )
            return
        if kind == "health_all_ok":
            _emit({"type": "health_all_ok", "health_all_ok": bool(sample)})
            return
        if kind == "in_air":
            _emit({"type": "in_air", "in_air": bool(sample)})
            return
        if kind == "landed_state":
            _emit({"type": "landed_state", "landed_state": str(sample)})
            return
        if kind == "rc_status":
            _emit(
                {
                    "type": "rc_status",
                    "rc_was_available_once": sample.was_available_once,
                    "rc_is_available": sample.is_available,
                    "rc_signal_strength_pct": _f(sample.signal_strength_percent),
                }
            )
            return
        if kind == "attitude_euler":
            _emit(
                {
                    "type": "attitude_euler",
                    "roll_deg": _f(sample.roll_deg),
                    "pitch_deg": _f(sample.pitch_deg),
                    "yaw_deg": _f(sample.yaw_deg),
                    "attitude_timestamp_us": _i(getattr(sample, "timestamp_us", None)),
                }
            )
            return
        if kind == "attitude_quaternion":
            _emit(
                {
                    "type": "attitude_quaternion",
                    "quat_w": _f(sample.w),
                    "quat_x": _f(sample.x),
                    "quat_y": _f(sample.y),
                    "quat_z": _f(sample.z),
                    "quat_timestamp_us": _i(getattr(sample, "timestamp_us", None)),
                }
            )
            return
        if kind == "attitude_angular_velocity_body":
            _emit(
                {
                    "type": "attitude_angular_velocity_body",
                    "ang_vel_roll_rad_s": _f(sample.roll_rad_s),
                    "ang_vel_pitch_rad_s": _f(sample.pitch_rad_s),
                    "ang_vel_yaw_rad_s": _f(sample.yaw_rad_s),
                }
            )
            return
        if kind == "velocity_ned":
            _emit(
                {
                    "type": "velocity_ned",
                    "north_m_s": _f(sample.north_m_s),
                    "east_m_s": _f(sample.east_m_s),
                    "down_m_s": _f(sample.down_m_s),
                }
            )
            return
        if kind == "altitude":
            _emit(
                {
                    "type": "altitude",
                    "alt_monotonic_m": _f(sample.altitude_monotonic_m),
                    "alt_amsl_m": _f(sample.altitude_amsl_m),
                    "alt_local_m": _f(sample.altitude_local_m),
                    "alt_relative_m": _f(sample.altitude_relative_m),
                    "alt_terrain_m": _f(sample.altitude_terrain_m),
                    "alt_bottom_clearance_m": _f(sample.bottom_clearance_m),
                }
            )
            return
        if kind == "home":
            _emit(
                {
                    "type": "home",
                    "home_lat_deg": _f(sample.latitude_deg),
                    "home_lon_deg": _f(sample.longitude_deg),
                    "home_abs_alt_m": _f(sample.absolute_altitude_m),
                    "home_rel_alt_m": _f(sample.relative_altitude_m),
                }
            )
            return
        if kind == "status_text":
            stype = getattr(sample, "type", None)
            _emit(
                {
                    "type": "status_text",
                    "status_severity": str(stype) if stype is not None else None,
                    "status_text": getattr(sample, "text", None),
                }
            )
            return
        if kind == "position_velocity_ned":
            pos = sample.position
            vel = sample.velocity
            _emit(
                {
                    "type": "position_velocity_ned",
                    "pos_vel_north_m": _f(pos.north_m),
                    "pos_vel_east_m": _f(pos.east_m),
                    "pos_vel_down_m": _f(pos.down_m),
                    "pos_vel_vn_m_s": _f(vel.north_m_s),
                    "pos_vel_ve_m_s": _f(vel.east_m_s),
                    "pos_vel_vd_m_s": _f(vel.down_m_s),
                }
            )
            return
        if kind == "heading":
            _emit({"type": "heading", "heading_deg": _f(sample.heading_deg)})
            return
        if kind == "distance_sensor":
            ori = sample.orientation
            _emit(
                {
                    "type": "distance_sensor",
                    "dist_min_m": _f(sample.minimum_distance_m),
                    "dist_max_m": _f(sample.maximum_distance_m),
                    "dist_cur_m": _f(sample.current_distance_m),
                    "dist_orient_roll_deg": _f(getattr(ori, "roll_deg", None)),
                    "dist_orient_pitch_deg": _f(getattr(ori, "pitch_deg", None)),
                    "dist_orient_yaw_deg": _f(getattr(ori, "yaw_deg", None)),
                }
            )
            return
        if kind == "wind":
            _emit(
                {
                    "type": "wind",
                    "wind_x_ned_m_s": _f(sample.wind_x_ned_m_s),
                    "wind_y_ned_m_s": _f(sample.wind_y_ned_m_s),
                    "wind_z_ned_m_s": _f(sample.wind_z_ned_m_s),
                }
            )
            return
        if kind == "imu":
            a = sample.acceleration_frd
            g = sample.angular_velocity_frd
            m = sample.magnetic_field_frd
            _emit(
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
                }
            )
            return
        if kind == "scaled_pressure":
            _emit(
                {
                    "type": "scaled_pressure",
                    "press_abs_hpa": _f(sample.absolute_pressure_hpa),
                    "press_diff_hpa": _f(sample.differential_pressure_hpa),
                    "press_temp_degc": _f(sample.temperature_deg),
                }
            )
            return
        if kind == "fixedwing_metrics":
            _emit(
                {
                    "type": "fixedwing_metrics",
                    "fw_airspeed_m_s": _f(sample.airspeed_m_s),
                    "fw_throttle_pct": _f(sample.throttle_percentage),
                    "fw_climb_m_s": _f(sample.climb_rate_m_s),
                    "fw_gspeed_m_s": _f(sample.groundspeed_m_s),
                    "fw_heading_deg": _f(sample.heading_deg),
                    "fw_abs_alt_m": _f(sample.absolute_altitude_m),
                }
            )
            return
        if kind == "vtol_state":
            _emit({"type": "vtol_state", "vtol_state": str(sample)})
            return
        if kind == "odometry":
            q = sample.q
            pb = sample.position_body
            vb = sample.velocity_body
            _emit(
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
                }
            )
            return
        if kind == "raw_gps":
            _emit(
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
                }
            )
            return
        if kind == "unix_epoch_time":
            _emit({"type": "unix_epoch_time", "unix_epoch_us": _i(sample)})
            return

    await asyncio.gather(
        _watch("armed", drone.telemetry.armed),
        _watch("flight_mode", drone.telemetry.flight_mode),
        _watch("position", drone.telemetry.position),
        _watch("battery", drone.telemetry.battery),
        _watch("gps_info", drone.telemetry.gps_info),
        _watch("health", drone.telemetry.health),
        _watch("health_all_ok", drone.telemetry.health_all_ok),
        _watch("in_air", drone.telemetry.in_air),
        _watch("landed_state", drone.telemetry.landed_state),
        _watch("rc_status", drone.telemetry.rc_status),
        _watch("attitude_euler", drone.telemetry.attitude_euler),
        _watch("attitude_quaternion", drone.telemetry.attitude_quaternion),
        _watch(
            "attitude_angular_velocity_body",
            drone.telemetry.attitude_angular_velocity_body,
        ),
        _watch("velocity_ned", drone.telemetry.velocity_ned),
        _watch("altitude", drone.telemetry.altitude),
        _watch("home", drone.telemetry.home),
        _watch("status_text", drone.telemetry.status_text),
        _watch("position_velocity_ned", drone.telemetry.position_velocity_ned),
        _watch("heading", drone.telemetry.heading),
        _watch("distance_sensor", drone.telemetry.distance_sensor),
        _watch("wind", drone.telemetry.wind),
        _watch("imu", drone.telemetry.imu),
        _watch("scaled_pressure", drone.telemetry.scaled_pressure),
        _watch("fixedwing_metrics", drone.telemetry.fixedwing_metrics),
        _watch("vtol_state", drone.telemetry.vtol_state),
        _watch("odometry", drone.telemetry.odometry),
        _watch("raw_gps", drone.telemetry.raw_gps),
        _watch("unix_epoch_time", drone.telemetry.unix_epoch_time),
    )


def main() -> None:
    host = os.environ.get("GUARDIAN_MAVSDK_GRPC_HOST", "127.0.0.1")
    port_s = os.environ.get("GUARDIAN_MAVSDK_GRPC_PORT", "50051")
    if len(sys.argv) >= 2:
        host = sys.argv[1]
    if len(sys.argv) >= 3:
        port_s = sys.argv[2]
    try:
        port = int(port_s)
    except ValueError:
        _emit({"type": "bridge_error", "message": f"bad_port:{port_s}"})
        sys.exit(1)

    try:
        asyncio.run(_run(host, port))
    except KeyboardInterrupt:
        pass


if __name__ == "__main__":
    main()
