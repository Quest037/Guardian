from guardian_ros2_vehicle_bridge.px4_topics import discover_px4_output_topics


def test_discover_all_present():
    expected = {
        "vehicle_status": "/fmu/out/vehicle_status",
        "battery_status": "/fmu/out/battery_status",
    }
    graph = [
        ("/fmu/out/vehicle_status", ["px4_msgs/msg/VehicleStatus"]),
        ("/fmu/out/battery_status", ["px4_msgs/msg/BatteryStatus"]),
        ("/other", ["std_msgs/msg/String"]),
    ]
    result = discover_px4_output_topics(graph, expected)
    assert result.all_present
    assert result.missing_keys() == []


def test_discover_degraded():
    expected = {"vehicle_status": "/fmu/out/vehicle_status"}
    graph = [("/fmu/out/battery_status", ["px4_msgs/msg/BatteryStatus"])]
    result = discover_px4_output_topics(graph, expected)
    assert not result.all_present
    assert result.missing_keys() == ["vehicle_status"]
