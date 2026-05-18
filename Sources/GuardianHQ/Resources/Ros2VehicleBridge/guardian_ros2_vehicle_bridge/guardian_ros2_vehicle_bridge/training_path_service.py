"""Handles Training ``plan_path`` stdin commands on the ROS 2 bridge supervisor."""

from __future__ import annotations

from typing import Any

from guardian_ros2_vehicle_bridge.json_emit import emit
from guardian_ros2_vehicle_bridge.nav2_path_planner import plan_training_path
from guardian_ros2_vehicle_bridge.nav2_training_stack import (
    Nav2TrainingStack,
    training_plan_namespace,
)


def handle_plan_path(
    cmd: dict[str, Any],
    supervisor_node: Any | None,
) -> None:
    request_id = str(cmd.get("request_id", "")).strip()
    vehicle_id = str(cmd.get("vehicle_id", "")).strip()
    if not request_id or not vehicle_id:
        emit(
            {
                "type": "ros2_nav2_plan_path",
                "request_id": request_id or "missing",
                "vehicle_id": vehicle_id,
                "ok": False,
                "message": "missing_request_id_or_vehicle_id",
                "source": "error",
                "points": [],
            }
        )
        return

    try:
        start = cmd.get("start") or {}
        goal = cmd.get("goal") or {}
        start_lat = float(start["lat"])
        start_lon = float(start["lon"])
        start_hdg = float(start.get("heading_deg", 0.0))
        goal_lat = float(goal["lat"])
        goal_lon = float(goal["lon"])
        goal_hdg = float(goal.get("heading_deg", 0.0))
        namespace = training_plan_namespace(str(cmd.get("ros_namespace", "") or ""))
    except (KeyError, TypeError, ValueError) as exc:
        emit(
            {
                "type": "ros2_nav2_plan_path",
                "request_id": request_id,
                "vehicle_id": vehicle_id,
                "ok": False,
                "message": f"bad_pose:{exc}",
                "source": "error",
                "points": [],
            }
        )
        return

    Nav2TrainingStack.shared().ensure_running_async()

    points, source = plan_training_path(
        supervisor_node,
        namespace,
        start_lat,
        start_lon,
        start_hdg,
        goal_lat,
        goal_lon,
        goal_hdg,
    )
    emit(
        {
            "type": "ros2_nav2_plan_path",
            "request_id": request_id,
            "vehicle_id": vehicle_id,
            "ok": True,
            "source": source,
            "points": points,
        }
    )
