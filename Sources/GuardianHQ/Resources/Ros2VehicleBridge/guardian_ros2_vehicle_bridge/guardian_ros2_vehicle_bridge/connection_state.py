"""ROS 2 bridge connection lifecycle states."""

from __future__ import annotations

from enum import Enum


class Ros2ConnectionState(str, Enum):
    """Internal connection health for one configured vehicle."""

    DISCONNECTED = "DISCONNECTED"
    CONNECTING = "CONNECTING"
    CONNECTED = "CONNECTED"
    DEGRADED = "DEGRADED"
    ERROR = "ERROR"

    def to_json(self) -> str:
        return self.value
