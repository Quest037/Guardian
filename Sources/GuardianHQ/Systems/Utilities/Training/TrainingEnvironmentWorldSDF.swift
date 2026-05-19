import Foundation

/// Generates Harmonic `world.sdf` files for open-field training environments.
enum TrainingEnvironmentWorldSDF {
    static let defaultWorldName = "guardian_open_field"

    /// Reads the `<world name="…">` from a training environment SDF (first world wins).
    static func parseWorldName(from worldURL: URL) -> String? {
        guard let raw = try? String(contentsOf: worldURL, encoding: .utf8) else { return nil }
        return parseWorldName(fromSDFXML: raw)
    }

    static func parseWorldName(fromSDFXML xml: String) -> String? {
        let pattern = #"<world\s+[^>]*name\s*=\s*["']([^"']+)["']"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let match = regex.firstMatch(in: xml, range: NSRange(xml.startIndex..., in: xml)),
              match.numberOfRanges > 1,
              let range = Range(match.range(at: 1), in: xml)
        else { return nil }
        return String(xml[range])
    }

    static func writeOpenFieldWorld(to url: URL, floorSideM: Double) throws {
        let side = max(1, floorSideM)
        let sideText = side.truncatingRemainder(dividingBy: 1) == 0
            ? String(format: "%.0f", side)
            : String(format: "%.3f", side)
        let xml = """
        <?xml version="1.0" ?>
        <sdf version="1.9">
          <world name="\(defaultWorldName)">
            <physics name="1ms" type="ignored">
              <max_step_size>0.001</max_step_size>
              <real_time_factor>1.0</real_time_factor>
            </physics>
            <plugin filename="gz-sim-physics-system" name="gz::sim::systems::Physics"></plugin>
            <plugin filename="gz-sim-user-commands-system" name="gz::sim::systems::UserCommands"></plugin>
            <plugin filename="gz-sim-scene-broadcaster-system" name="gz::sim::systems::SceneBroadcaster"></plugin>

            <scene>
              <ambient>0.45 0.45 0.45 1</ambient>
              <background>0.55 0.58 0.62 1</background>
            </scene>

            <light type="directional" name="sun">
              <cast_shadows>true</cast_shadows>
              <pose>0 0 10 0.3 0.5 0</pose>
              <diffuse>0.95 0.95 0.95 1</diffuse>
              <specular>0.2 0.2 0.2 1</specular>
            </light>

            <model name="open_field_floor">
              <static>true</static>
              <pose>0 0 -0.05 0 0 0</pose>
              <link name="link">
                <collision name="collision">
                  <geometry>
                    <box>
                      <size>\(sideText) \(sideText) 0.1</size>
                    </box>
                  </geometry>
                </collision>
                <visual name="visual">
                  <geometry>
                    <box>
                      <size>\(sideText) \(sideText) 0.1</size>
                    </box>
                  </geometry>
                  <material>
                    <ambient>1 1 1 1</ambient>
                    <diffuse>1 1 1 1</diffuse>
                    <specular>0.05 0.05 0.05 1</specular>
                  </material>
                </visual>
              </link>
            </model>
          </world>
        </sdf>
        """
        try xml.write(to: url, atomically: true, encoding: .utf8)
    }
}
