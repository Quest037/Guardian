import unittest

from guardian.platform.integrations import detect_platform_info


class PlatformIntegrationTests(unittest.TestCase):
    def test_detect_platform_info_has_expected_fields(self) -> None:
        info = detect_platform_info()
        self.assertTrue(info.os_name)
        self.assertTrue(info.os_version)
        self.assertIsInstance(info.is_supported, bool)
        self.assertIsInstance(info.supports_notifications, bool)
        self.assertIsInstance(info.supports_global_shortcuts, bool)


if __name__ == "__main__":
    unittest.main()
