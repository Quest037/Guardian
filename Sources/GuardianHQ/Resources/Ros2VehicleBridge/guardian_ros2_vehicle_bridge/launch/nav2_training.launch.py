"""Guardian Training — minimal Nav2 (map + global planner) for Leaflet path overlay."""

import os

from ament_index_python.packages import get_package_share_directory
from launch import LaunchDescription
from launch.actions import DeclareLaunchArgument
from launch.substitutions import LaunchConfiguration
from launch_ros.actions import Node
from launch_ros.descriptions import ParameterFile
from nav2_common.launch import RewrittenYaml


def generate_launch_description() -> LaunchDescription:
    pkg_share = get_package_share_directory("guardian_ros2_vehicle_bridge")
    params_file = os.path.join(pkg_share, "config", "nav2_training_params.yaml")
    default_map = os.path.join(pkg_share, "maps", "training_open_field.yaml")

    use_sim_time = LaunchConfiguration("use_sim_time")
    map_yaml_file = LaunchConfiguration("map")
    autostart = LaunchConfiguration("autostart")

    param_substitutions = {
        "use_sim_time": use_sim_time,
        "yaml_filename": map_yaml_file,
    }
    configured_params = ParameterFile(
        RewrittenYaml(
            source_file=params_file,
            param_rewrites=param_substitutions,
            convert_types=True,
        ),
        allow_substs=True,
    )

    lifecycle_nodes = ["map_server", "planner_server"]

    return LaunchDescription(
        [
            DeclareLaunchArgument("use_sim_time", default_value="false"),
            DeclareLaunchArgument("map", default_value=default_map),
            DeclareLaunchArgument("autostart", default_value="true"),
            Node(
                package="tf2_ros",
                executable="static_transform_publisher",
                name="map_to_odom",
                arguments=["0", "0", "0", "0", "0", "0", "map", "odom"],
            ),
            Node(
                package="tf2_ros",
                executable="static_transform_publisher",
                name="odom_to_base_link",
                arguments=["0", "0", "0", "0", "0", "0", "odom", "base_link"],
            ),
            Node(
                package="nav2_map_server",
                executable="map_server",
                name="map_server",
                output="screen",
                parameters=[configured_params],
            ),
            Node(
                package="nav2_planner",
                executable="planner_server",
                name="planner_server",
                output="screen",
                parameters=[configured_params],
            ),
            Node(
                package="nav2_lifecycle_manager",
                executable="lifecycle_manager",
                name="lifecycle_manager_training",
                output="screen",
                parameters=[
                    {"use_sim_time": use_sim_time},
                    {"autostart": autostart},
                    {"node_names": lifecycle_nodes},
                ],
            ),
        ]
    )
