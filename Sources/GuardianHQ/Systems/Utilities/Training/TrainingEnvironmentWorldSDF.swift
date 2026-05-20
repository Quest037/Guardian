import Foundation

/// Generates Harmonic `world.sdf` files for open-field training environments.
enum TrainingEnvironmentWorldSDF {
    static let defaultWorldName = "guardian_open_field"

    /// Map-base square depth (m). Top face stays at z = 0; block extends downward.
    static let openFieldFloorDepthM: Double = 10

    /// Open-field floor plate: top `#ffffff`, bottom `#fbffce` (static box, top face at z = 0).
    enum OpenFieldFloorColors {
        static let topDiffuse = "1.000 1.000 1.000"
        static let bottomDiffuse = "0.984 1.000 0.808"
    }

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

    /// Reads `open_field_floor` collision `<size>` X dimension (square floor side, metres).
    static func parseOpenFieldFloorSideM(from worldURL: URL) -> Double? {
        guard let raw = try? String(contentsOf: worldURL, encoding: .utf8) else { return nil }
        return parseOpenFieldFloorSideM(fromSDFXML: raw)
    }

    static func parseOpenFieldFloorSideM(fromSDFXML xml: String) -> Double? {
        let pattern =
            #"<model\s+name\s*=\s*["']open_field_floor["'][\s\S]*?<collision[\s\S]*?<size>\s*([0-9.]+)\s+([0-9.]+)"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let match = regex.firstMatch(in: xml, range: NSRange(xml.startIndex..., in: xml)),
              match.numberOfRanges > 2,
              let xRange = Range(match.range(at: 1), in: xml),
              let yRange = Range(match.range(at: 2), in: xml),
              let x = Double(xml[xRange]),
              let y = Double(xml[yRange]),
              x > 0,
              y > 0
        else { return nil }
        return max(x, y)
    }

    static func writeOpenFieldWorld(
        to url: URL,
        floorSideM: Double,
        additionalModelsXML: String = ""
    ) throws {
        let side = max(1, floorSideM)
        let sideText = formatMetres(side)
        let depth = max(0.1, openFieldFloorDepthM)
        let depthText = formatMetres(depth)
        let halfDepth = depth / 2
        let halfDepthText = formatMetres(halfDepth)
        let collisionCenterZText = formatMetres(-halfDepth)
        let bottomVisualCenterZText = formatMetres(-depth + halfDepth / 2)
        let topVisualCenterZText = formatMetres(-halfDepth / 2)
        let floorVisuals = openFieldFloorVisualsXML(
            sideText: sideText,
            halfDepthText: halfDepthText,
            bottomVisualCenterZText: bottomVisualCenterZText,
            topVisualCenterZText: topVisualCenterZText
        )
        let extra = additionalModelsXML.isEmpty ? "" : "\n\(additionalModelsXML)"
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
              <pose>0 0 \(collisionCenterZText) 0 0 0</pose>
              <link name="link">
                <collision name="collision">
                  <geometry>
                    <box>
                      <size>\(sideText) \(sideText) \(depthText)</size>
                    </box>
                  </geometry>
                </collision>
        \(floorVisuals)
              </link>
            </model>
        \(extra)
          </world>
        </sdf>
        """
        try xml.write(to: url, atomically: true, encoding: .utf8)
    }

    /// Two half-thickness visuals so the top face is white and the underside is `#fbffce`.
    static func openFieldFloorVisualsXML(
        sideText: String,
        halfDepthText: String,
        bottomVisualCenterZText: String,
        topVisualCenterZText: String
    ) -> String {
        """
                <visual name="visual_bottom">
                  <pose>0 0 \(bottomVisualCenterZText) 0 0 0</pose>
                  <geometry>
                    <box>
                      <size>\(sideText) \(sideText) \(halfDepthText)</size>
                    </box>
                  </geometry>
                  <material>
                    <ambient>\(OpenFieldFloorColors.bottomDiffuse) 1</ambient>
                    <diffuse>\(OpenFieldFloorColors.bottomDiffuse) 1</diffuse>
                    <specular>0.05 0.05 0.05 1</specular>
                  </material>
                </visual>
                <visual name="visual_top">
                  <pose>0 0 \(topVisualCenterZText) 0 0 0</pose>
                  <geometry>
                    <box>
                      <size>\(sideText) \(sideText) \(halfDepthText)</size>
                    </box>
                  </geometry>
                  <material>
                    <ambient>\(OpenFieldFloorColors.topDiffuse) 1</ambient>
                    <diffuse>\(OpenFieldFloorColors.topDiffuse) 1</diffuse>
                    <specular>0.05 0.05 0.05 1</specular>
                  </material>
                </visual>
        """
    }

    private static func formatMetres(_ value: Double) -> String {
        value.truncatingRemainder(dividingBy: 1) == 0
            ? String(format: "%.0f", value)
            : String(format: "%.3f", value)
    }
}
