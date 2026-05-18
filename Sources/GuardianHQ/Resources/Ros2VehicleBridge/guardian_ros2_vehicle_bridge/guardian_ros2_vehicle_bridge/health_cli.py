#!/usr/bin/env python3
"""
One-shot ROS 2 health check: lists PX4 ``fmu/out`` topics and prints connection summary.

Does not start the full multi-vehicle bridge. Useful beside PX4 SITL + Micro XRCE-DDS Agent.
"""

from __future__ import annotations

import argparse
import sys
import time

import rclpy
from rclpy.node import Node

from guardian_ros2_vehicle_bridge.px4_topics import PX4_BASIC_OUTPUT_TOPICS, discover_px4_output_topics
from guardian_ros2_vehicle_bridge.vehicle_config import VehicleConnectionConfig


class _HealthProbe(Node):
    def __init__(self, namespace: str) -> None:
        super().__init__("guardian_ros2_health_probe")
        self._cfg = VehicleConnectionConfig(
            vehicle_id="health_probe",
            ros_namespace=namespace,
        )
        self._expected = {
            key: self._cfg.topic_fqn(rel) for key, rel in PX4_BASIC_OUTPUT_TOPICS.items()
        }

    def run_probe(self, wait_s: float) -> int:
        deadline = time.monotonic() + wait_s
        while time.monotonic() < deadline:
            rclpy.spin_once(self, timeout_sec=0.2)
            discovery = discover_px4_output_topics(self.get_topic_names_and_types(), self._expected)
            if discovery.all_present:
                break
            time.sleep(0.3)

        discovery = discover_px4_output_topics(self.get_topic_names_and_types(), self._expected)
        print("Guardian ROS 2 / PX4 topic health check")
        print(f"  ROS namespace: {self._cfg.normalized_namespace() or '(default /fmu/...)'}")
        print(f"  Waited up to: {wait_s:.1f}s")
        print("")
        for key, fqn in self._expected.items():
            ok = discovery.present.get(key, False)
            types = discovery.advertised_types.get(key, [])
            mark = "OK" if ok else "MISSING"
            type_hint = f"  types={types}" if types else ""
            print(f"  [{mark}] {key}: {fqn}{type_hint}")

        missing = discovery.missing_keys()
        if not discovery.any_present:
            print("\nResult: NO PX4 ROS 2 topics visible. Is Micro XRCE-DDS Agent running? Is PX4 publishing?")
            return 2
        if missing:
            print(f"\nResult: DEGRADED — missing: {', '.join(missing)}")
            return 1
        print("\nResult: HEALTHY — all basic PX4 output topics are advertised.")
        return 0


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Guardian PX4 ROS 2 topic health check")
    parser.add_argument(
        "--namespace",
        default="",
        help="PX4 ROS namespace prefix (e.g. px4_0). Empty uses /fmu/out/... at root.",
    )
    parser.add_argument(
        "--wait",
        type=float,
        default=8.0,
        help="Seconds to wait for topics to appear",
    )
    args = parser.parse_args(argv)

    rclpy.init()
    node = _HealthProbe(namespace=args.namespace)
    try:
        code = node.run_probe(args.wait)
    finally:
        node.destroy_node()
        rclpy.shutdown()
    return code


if __name__ == "__main__":
    sys.exit(main())
