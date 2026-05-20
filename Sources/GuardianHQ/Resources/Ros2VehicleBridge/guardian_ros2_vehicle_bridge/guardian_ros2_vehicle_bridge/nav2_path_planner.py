"""Nav2 path planning for Training (ComputePathToPose when stack is up; geodesic fallback)."""

from __future__ import annotations

import math
from typing import Any

from guardian_ros2_vehicle_bridge.geodetic_path_planner import plan_geodetic_path, path_to_route_coordinates
from guardian_ros2_vehicle_bridge.nav2_planner_availability import TRAINING_COMPUTE_PATH_ACTION_CANDIDATES
from guardian_ros2_vehicle_bridge.nav2_training_stack import Nav2TrainingStack


def _latlon_to_local_m(
    lat: float, lon: float, origin_lat: float, origin_lon: float
) -> tuple[float, float]:
    r = 6_378_137.0
    north = math.radians(lat - origin_lat) * r
    east = math.radians(lon - origin_lon) * r * math.cos(math.radians(origin_lat))
    return north, east


def _local_to_latlon(
    north_m: float, east_m: float, origin_lat: float, origin_lon: float
) -> tuple[float, float]:
    r = 6_378_137.0
    lat = origin_lat + math.degrees(north_m / r)
    lon = origin_lon + math.degrees(east_m / (r * math.cos(math.radians(origin_lat))))
    return lat, lon


def _yaw_to_quaternion_z_w(yaw_rad: float) -> tuple[float, float, float, float]:
    half = yaw_rad * 0.5
    return (0.0, 0.0, math.sin(half), math.cos(half))


def _compute_path_action_candidates(namespace: str) -> tuple[str, ...]:
    ns = namespace.strip("/")
    primary = f"/{ns}/compute_path_to_pose" if ns else "/compute_path_to_pose"
    ordered = [primary]
    for name in TRAINING_COMPUTE_PATH_ACTION_CANDIDATES:
        if name not in ordered:
            ordered.append(name)
    return tuple(ordered)


def try_nav2_compute_path(
    node: Any,
    namespace: str,
    start_lat: float,
    start_lon: float,
    start_heading_deg: float,
    goal_lat: float,
    goal_lon: float,
    goal_heading_deg: float,
    *,
    timeout_s: float = 8.0,
) -> list[dict[str, float]] | None:
    """
    Call Nav2 ``ComputePathToPose`` action when the planner server is active.

    Returns None when Nav2 is not installed, not running, or the call fails.
    """
    try:
        from nav2_msgs.action import ComputePathToPose  # type: ignore
        from geometry_msgs.msg import PoseStamped  # type: ignore
        from builtin_interfaces.msg import Time  # type: ignore
        from rclpy.action import ActionClient  # type: ignore
    except ImportError:
        return None

    action_name: str | None = None
    client: Any = None
    wait_budget = min(timeout_s, 3.0)
    for candidate in _compute_path_action_candidates(namespace):
        probe = ActionClient(node, ComputePathToPose, candidate)
        if probe.wait_for_server(timeout_sec=wait_budget):
            action_name = candidate
            client = probe
            break
    if client is None or action_name is None:
        return None

    origin_lat, origin_lon = start_lat, start_lon
    s_n, s_e = _latlon_to_local_m(start_lat, start_lon, origin_lat, origin_lon)
    g_n, g_e = _latlon_to_local_m(goal_lat, goal_lon, origin_lat, origin_lon)
    start_yaw = math.radians(start_heading_deg)
    goal_yaw = math.radians(goal_heading_deg)

    def pose(x: float, y: float, yaw: float) -> PoseStamped:
        qx, qy, qz, qw = _yaw_to_quaternion_z_w(yaw)
        msg = PoseStamped()
        msg.header.frame_id = "map"
        msg.header.stamp = Time(sec=0, nanosec=0)
        msg.pose.position.x = x
        msg.pose.position.y = y
        msg.pose.position.z = 0.0
        msg.pose.orientation.x = qx
        msg.pose.orientation.y = qy
        msg.pose.orientation.z = qz
        msg.pose.orientation.w = qw
        return msg

    goal_msg = ComputePathToPose.Goal()
    goal_msg.start = pose(s_e, s_n, start_yaw)
    goal_msg.goal = pose(g_e, g_n, goal_yaw)
    goal_msg.planner_id = ""
    goal_msg.use_start = True

    rclpy = __import__("rclpy")
    send_future = client.send_goal_async(goal_msg)
    rclpy.spin_until_future_complete(node, send_future, timeout_sec=timeout_s)
    if not send_future.done():
        return None
    goal_handle = send_future.result()
    if goal_handle is None or not goal_handle.accepted:
        return None

    result_future = goal_handle.get_result_async()
    rclpy.spin_until_future_complete(node, result_future, timeout_sec=timeout_s)
    if not result_future.done():
        return None
    action_result = result_future.result()
    if action_result is None:
        return None
    path = action_result.result.path
    if path is None or len(path.poses) < 2:
        return None

    out: list[dict[str, float]] = []
    for ps in path.poses:
        lat, lon = _local_to_latlon(
            ps.pose.position.y, ps.pose.position.x, origin_lat, origin_lon
        )
        out.append({"lat": lat, "lon": lon})
    return out


def plan_training_path(
    node: Any | None,
    namespace: str,
    start_lat: float,
    start_lon: float,
    start_heading_deg: float,
    goal_lat: float,
    goal_lon: float,
    goal_heading_deg: float,
) -> tuple[list[dict[str, float]], str]:
    """
    Plan A→B for Training map overlay.

    Returns (points as {lat, lon}, source) where source is ``nav2`` or ``geodesic_fallback``.
    """
    if node is not None and Nav2TrainingStack.shared().is_ready:
        nav2_pts = try_nav2_compute_path(
            node,
            namespace,
            start_lat,
            start_lon,
            start_heading_deg,
            goal_lat,
            goal_lon,
            goal_heading_deg,
        )
        if nav2_pts and len(nav2_pts) >= 2:
            return path_to_route_coordinates(nav2_pts), "nav2"

    geodetic = plan_geodetic_path(
        start_lat,
        start_lon,
        start_heading_deg,
        goal_lat,
        goal_lon,
        goal_heading_deg,
    )
    return path_to_route_coordinates(geodetic), "geodesic_fallback"
