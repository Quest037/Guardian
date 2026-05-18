"""Line-delimited JSON on stdout (Guardian app integration hook; parallel to mavsdk_bridge.py)."""

from __future__ import annotations

import json
import sys
from typing import Any


def emit(obj: dict[str, Any]) -> None:
    print(json.dumps(obj, separators=(",", ":"), allow_nan=False), flush=True)


def emit_vehicle(vehicle_id: str, obj: dict[str, Any]) -> None:
    payload = dict(obj)
    payload["vehicle_id"] = vehicle_id
    emit(payload)


def log_err(msg: str) -> None:
    print(msg, file=sys.stderr, flush=True)
