#!/usr/bin/env python3
"""
Guardian ROS 2 vehicle bridge — multi-vehicle PX4 uXRCE-DDS sidecar.

Runs one rclpy node per configured vehicle. JSON lines on stdout (health / discovery)
mirror ``mavsdk_bridge.py`` for future GuardianHQ integration.

MAVSDK remains the primary bridge for arming, modes, missions, and fleet management.
This process only establishes ROS 2 subscriptions and connection health.

Usage:
  ros2 run guardian_ros2_vehicle_bridge guardian_ros2_vehicle_bridge --config /path/vehicles.yaml
  # or after colcon install:
  GUARDIAN_ROS2_BRIDGE_CONFIG=... guardian_ros2_vehicle_bridge

Stdin commands (newline-delimited JSON):
  {"type": "set_vehicles", "vehicles": [{...}, ...]}
"""

from __future__ import annotations

import argparse
import json
import os
import select
import sys
import threading
import traceback
from typing import Any

import rclpy
from rclpy.executors import MultiThreadedExecutor
from rclpy.node import Node

from guardian_ros2_vehicle_bridge.autonomy_planner_coordinator import AutonomyPlannerCoordinator
from guardian_ros2_vehicle_bridge.connection_registry import VehicleConnectionRegistry
from guardian_ros2_vehicle_bridge.connection_state import Ros2ConnectionState
from guardian_ros2_vehicle_bridge.json_emit import emit, emit_vehicle, log_err
from guardian_ros2_vehicle_bridge.px4_vehicle_node import Px4VehicleConnectionNode
from guardian_ros2_vehicle_bridge.nav2_training_stack import Nav2TrainingStack
from guardian_ros2_vehicle_bridge.training_path_service import handle_plan_path
from guardian_ros2_vehicle_bridge.vehicle_config import BridgeConfig, VehicleConnectionConfig, load_bridge_config_from_env


class GuardianRos2BridgeSupervisor(Node):
    """Lightweight supervisor node (logging / future global ROS graph queries)."""

    def __init__(self) -> None:
        super().__init__("guardian_ros2_bridge_supervisor")


def _parse_vehicles_command(cmd: dict[str, Any]) -> list[VehicleConnectionConfig]:
    raw = cmd.get("vehicles", [])
    out: list[VehicleConnectionConfig] = []
    if not isinstance(raw, list):
        return out
    for item in raw:
        if isinstance(item, dict):
            try:
                out.append(VehicleConnectionConfig.from_mapping(item))
            except ValueError as exc:
                emit({"type": "ros2_bridge_error", "message": f"bad_vehicle_config:{exc}"})
    return out


def _stdin_reader(stop_event: threading.Event, command_queue: list[dict[str, Any]]) -> None:
    while not stop_event.is_set():
        ready, _, _ = select.select([sys.stdin], [], [], 0.25)
        if not ready:
            continue
        line = sys.stdin.readline()
        if not line:
            continue
        text = line.decode("utf-8", errors="ignore").strip() if isinstance(line, bytes) else line.strip()
        if not text:
            continue
        try:
            cmd = json.loads(text)
        except json.JSONDecodeError:
            emit({"type": "ros2_bridge_error", "message": "bad_command_json"})
            continue
        if isinstance(cmd, dict):
            command_queue.append(cmd)


def main(argv: list[str] | None = None) -> None:
    parser = argparse.ArgumentParser(description="Guardian PX4 ROS 2 vehicle bridge")
    parser.add_argument(
        "--config",
        help="YAML vehicle list (overrides GUARDIAN_ROS2_BRIDGE_CONFIG)",
    )
    args = parser.parse_args(argv)

    config_path = (args.config or os.environ.get("GUARDIAN_ROS2_BRIDGE_CONFIG", "")).strip()
    bridge_config = BridgeConfig()
    if config_path:
        bridge_config = BridgeConfig.from_yaml_file(config_path)
    else:
        env_cfg = load_bridge_config_from_env()
        if env_cfg is not None:
            bridge_config = env_cfg

    rclpy.init()
    registry = VehicleConnectionRegistry()
    planner_coordinator = AutonomyPlannerCoordinator()
    supervisor = GuardianRos2BridgeSupervisor()
    executor = MultiThreadedExecutor()
    executor.add_node(supervisor)

    stale_s = bridge_config.stale_topic_s

    def node_factory(cfg: VehicleConnectionConfig) -> Px4VehicleConnectionNode:
        node = Px4VehicleConnectionNode(cfg, stale_topic_s=stale_s)
        executor.add_node(node)
        return node

    def reconcile(vehicles: list[VehicleConnectionConfig]) -> None:
        registry.reconcile(vehicles, node_factory, executor)
        planner_coordinator.reconcile(vehicles)
        emit(
            {
                "type": "ros2_bridge_vehicles_updated",
                "vehicle_ids": registry.keys(),
            }
        )

    reconcile(bridge_config.enabled_vehicles())

    boot: dict[str, Any] = {
        "type": "ros2_bridge_listening",
        "vehicle_ids": registry.keys(),
        "px4_msgs_hint": "install ros-$ROS_DISTRO-px4-msgs for subscriptions",
    }
    if config_path:
        boot["config"] = config_path
    emit(boot)

    # Fleet Nav2 warm-start: one global planner at bridge boot (not gated on plan_path or vehicles).
    Nav2TrainingStack.shared().ensure_running_async()

    command_queue: list[dict[str, Any]] = []
    stop_event = threading.Event()
    reader = threading.Thread(target=_stdin_reader, args=(stop_event, command_queue), daemon=True)
    reader.start()

    try:
        while rclpy.ok():
            executor.spin_once(timeout_sec=0.1)
            while command_queue:
                cmd = command_queue.pop(0)
                ctype = str(cmd.get("type", "")).strip().lower()
                if ctype == "set_vehicles":
                    vehicles = _parse_vehicles_command(cmd)
                    reconcile(vehicles)
                elif ctype == "plan_path":
                    handle_plan_path(cmd, supervisor)
                elif ctype == "ensure_nav2":
                    Nav2TrainingStack.shared().ensure_running_async()
                elif ctype == "shutdown":
                    break
                elif ctype:
                    emit({"type": "ros2_bridge_error", "message": f"unknown_command:{ctype}"})
    except KeyboardInterrupt:
        pass
    except Exception as exc:
        log_err(f"ros2 bridge runtime failed: {exc}\n{traceback.format_exc()}")
        emit({"type": "ros2_bridge_error", "message": f"runtime:{exc}"})
    finally:
        stop_event.set()
        for vid in registry.keys():
            emit_vehicle(
                vid,
                {
                    "type": "ros2_connection_state",
                    "state": Ros2ConnectionState.DISCONNECTED.to_json(),
                },
            )
        planner_coordinator.destroy_all()
        registry.destroy_all(executor)
        supervisor.destroy_node()
        if rclpy.ok():
            rclpy.shutdown()


if __name__ == "__main__":
    main()
