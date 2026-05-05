#!/usr/bin/env python3
"""
Guardian MAVSDK sidecar: gRPC to an already-running mavsdk_server; JSON lines on stdout.

Usage: python3 mavsdk_bridge.py [host] [port]
Env: GUARDIAN_MAVSDK_GRPC_HOST, GUARDIAN_MAVSDK_GRPC_PORT (defaults 127.0.0.1:50051)
"""

from __future__ import annotations

import asyncio
import json
import os
import sys
import traceback


def _emit(obj: dict) -> None:
    print(json.dumps(obj, separators=(",", ":")), flush=True)


def _err(msg: str) -> None:
    print(msg, file=sys.stderr, flush=True)


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
    # `connect()` blocks until MAVSDK discovers a system on the link (e.g. SITL or radio).
    # Emit first so the UI can show "waiting for aircraft" instead of a perpetual "connecting" spinner.
    _emit({"type": "bridge_listening", "host": host, "port": port})
    try:
        await drone.connect()
    except Exception as e:
        _err(f"connect failed: {e}\n{traceback.format_exc()}")
        _emit({"type": "bridge_error", "message": str(e)})
        sys.exit(2)

    _emit({"type": "bridge_ready", "host": host, "port": port})

    async def watch_armed():
        try:
            async for armed in drone.telemetry.armed():
                _emit({"type": "armed", "armed": bool(armed)})
        except asyncio.CancelledError:
            raise
        except Exception as e:
            _emit({"type": "bridge_error", "message": f"armed_stream:{e}"})

    async def watch_mode():
        try:
            async for mode in drone.telemetry.flight_mode():
                _emit({"type": "flight_mode", "flight_mode": str(mode)})
        except asyncio.CancelledError:
            raise
        except Exception as e:
            _emit({"type": "bridge_error", "message": f"mode_stream:{e}"})

    async def watch_position():
        try:
            async for pos in drone.telemetry.position():
                _emit(
                    {
                        "type": "position",
                        "lat_deg": pos.latitude_deg,
                        "lon_deg": pos.longitude_deg,
                        "rel_alt_m": pos.relative_altitude_m,
                    }
                )
        except asyncio.CancelledError:
            raise
        except Exception as e:
            _emit({"type": "bridge_error", "message": f"position_stream:{e}"})

    await asyncio.gather(
        watch_armed(),
        watch_mode(),
        watch_position(),
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
