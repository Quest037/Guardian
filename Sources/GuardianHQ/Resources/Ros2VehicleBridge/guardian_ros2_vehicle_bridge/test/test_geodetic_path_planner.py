import unittest

from guardian_ros2_vehicle_bridge.geodetic_path_planner import plan_geodetic_path


class GeodeticPathPlannerTests(unittest.TestCase):
    def test_plan_has_endpoints(self) -> None:
        path = plan_geodetic_path(-35.0, 149.0, 0.0, -35.0001, 149.0002, 90.0, step_m=5.0)
        self.assertGreaterEqual(len(path), 2)
        self.assertAlmostEqual(path[0]["lat"], -35.0, places=5)
        self.assertAlmostEqual(path[-1]["lat"], -35.0001, places=5)
        self.assertAlmostEqual(path[-1]["lon"], 149.0002, places=5)

    def test_short_path_minimum_two_points(self) -> None:
        path = plan_geodetic_path(0.0, 0.0, 0.0, 0.0, 0.0, 0.0, step_m=10.0)
        self.assertEqual(len(path), 2)


if __name__ == "__main__":
    unittest.main()
