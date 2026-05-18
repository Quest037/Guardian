from setuptools import find_packages, setup

package_name = "guardian_ros2_vehicle_bridge"

setup(
    name=package_name,
    version="0.1.0",
    packages=find_packages(exclude=["test"]),
    data_files=[
        ("share/ament_index/resource_index/packages", ["resource/" + package_name]),
        ("share/" + package_name, ["package.xml"]),
        (
            "share/" + package_name + "/launch",
            ["launch/vehicle_bridge.launch.py", "launch/nav2_training.launch.py"],
        ),
        (
            "share/" + package_name + "/config",
            ["config/vehicles.example.yaml", "config/nav2_training_params.yaml"],
        ),
        (
            "share/" + package_name + "/maps",
            ["maps/training_open_field.yaml", "maps/training_open_field.pgm"],
        ),
    ],
    install_requires=["setuptools"],
    zip_safe=True,
    maintainer="Guardian",
    maintainer_email="dev@guardian.local",
    description="Guardian PX4 ROS 2 vehicle connection sidecar",
    license="Proprietary",
    tests_require=["pytest"],
    test_suite="test",
    entry_points={
        "console_scripts": [
            "guardian_ros2_vehicle_bridge = guardian_ros2_vehicle_bridge.multi_vehicle_bridge:main",
            "guardian_ros2_health_check = guardian_ros2_vehicle_bridge.health_cli:main",
        ],
    },
)
