import Foundation

/// Locked ROS 2 sidecar defaults (not user-configurable).
enum Ros2BridgeRuntime {
    /// Micro XRCE-DDS Agent UDP port (PX4 `UXRCE_DDS_CFG` must match).
    static let microXrceUdpPort = 8888
}
