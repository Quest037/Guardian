import platform
from dataclasses import dataclass


@dataclass(frozen=True)
class PlatformInfo:
    os_name: str
    os_version: str
    is_supported: bool
    supports_notifications: bool
    supports_global_shortcuts: bool


def detect_platform_info() -> PlatformInfo:
    os_name = platform.system()
    os_version = platform.release()

    is_supported = os_name in {"Darwin", "Linux", "Windows"}
    supports_notifications = os_name in {"Darwin", "Linux", "Windows"}
    supports_global_shortcuts = os_name in {"Darwin", "Windows"}

    return PlatformInfo(
        os_name=os_name,
        os_version=os_version,
        is_supported=is_supported,
        supports_notifications=supports_notifications,
        supports_global_shortcuts=supports_global_shortcuts,
    )
