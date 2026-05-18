"""Launch Guardian ROS 2 vehicle bridge with a YAML vehicle list."""

from __future__ import annotations

import os

from ament_index_python.packages import get_package_share_directory
from launch import LaunchDescription
from launch.actions import DeclareLaunchArgument
from launch.substitutions import LaunchConfiguration
from launch_ros.actions import Node


def generate_launch_description() -> LaunchDescription:
    pkg_share = get_package_share_directory("guardian_ros2_vehicle_bridge")
    default_config = os.path.join(pkg_share, "config", "vehicles.example.yaml")

    config_arg = DeclareLaunchArgument(
        "config",
        default_value=os.environ.get("GUARDIAN_ROS2_BRIDGE_CONFIG", default_config),
        description="Path to vehicles YAML",
    )

    bridge_node = Node(
        package="guardian_ros2_vehicle_bridge",
        executable="guardian_ros2_vehicle_bridge",
        name="guardian_ros2_vehicle_bridge",
        output="screen",
        arguments=["--config", LaunchConfiguration("config")],
    )

    return LaunchDescription([config_arg, bridge_node])
