import Foundation

/// Writes a temporary Gazebo `model.sdf` (box fallback or optional custom mesh).
enum GazeboVehicleModelSDFWriter {
  struct WrittenModel: Equatable, Sendable {
    let modelName: String
    let sdfURL: URL
    let usesCustomMesh: Bool
  }

  static func writeTemporaryModel(
    modelName: String,
    params: GazeboVehicleSpawnParams,
    footprint: VehicleFootprint
  ) throws -> WrittenModel {
    let safeName = sanitizeModelName(modelName)
    let dir = FileManager.default.temporaryDirectory
      .appendingPathComponent("guardian-gazebo-vehicle-models", isDirectory: true)
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let sdfURL = dir.appendingPathComponent("model.sdf")

    let meshURI = params.customMeshURI?.trimmingCharacters(in: .whitespacesAndNewlines)
    let meshPath = meshURI.flatMap { resolvedMeshPath($0) }
    let usesMesh = meshPath != nil

    let xml = modelSDFXML(
      modelName: safeName,
      footprint: footprint,
      universalClass: params.vehicleClass.universalClass,
      meshFilePath: meshPath,
      materialRGBA: materialRGBA(for: params)
    )
    try xml.write(to: sdfURL, atomically: true, encoding: .utf8)
    return WrittenModel(modelName: safeName, sdfURL: sdfURL, usesCustomMesh: usesMesh)
  }

  static func sanitizeModelName(_ raw: String) -> String {
    let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_"))
    let cleaned = raw.unicodeScalars.map { allowed.contains($0) ? Character($0) : "_" }
    let joined = String(cleaned)
    let trimmed = joined.trimmingCharacters(in: CharacterSet(charactersIn: "_"))
    return trimmed.isEmpty ? "guardian_vehicle" : String(trimmed.prefix(48))
  }

  private static func resolvedMeshPath(_ token: String) -> String? {
    if token.hasPrefix("file://") {
      let path = String(token.dropFirst("file://".count))
      return FileManager.default.isReadableFile(atPath: path) ? path : nil
    }
    let expanded = (token as NSString).expandingTildeInPath
    if FileManager.default.isReadableFile(atPath: expanded) {
      return expanded
    }
    return nil
  }

  private static func materialRGBA(for params: GazeboVehicleSpawnParams) -> GazeboUniversalClassVisualStyle.RGBA {
    if let hex = params.squadColorHex?.trimmingCharacters(in: .whitespacesAndNewlines),
       !hex.isEmpty,
       let rgba = TrainingLabSquadFormationPalette.rgba(fromHex: hex) {
      return rgba
    }
    return GazeboUniversalClassVisualStyle.rgba(for: params.vehicleClass.universalClass)
  }

  static func modelSDFXML(
    modelName: String,
    footprint: VehicleFootprint,
    universalClass: UniversalVehicleClass,
    meshFilePath: String?,
    materialRGBA: GazeboUniversalClassVisualStyle.RGBA? = nil
  ) -> String {
    let metres = footprint.metres()
    let w = formatM(metres.widthM)
    let l = formatM(metres.lengthM)
    let h = formatM(metres.heightM)

    let collisionGeometry = """
                  <box>
                    <size>\(w) \(l) \(h)</size>
                  </box>
    """

    let color = materialRGBA ?? GazeboUniversalClassVisualStyle.rgba(for: universalClass)
    let visuals: String
    if let meshFilePath {
      let uri = "file://\(meshFilePath)"
      visuals = """
          <visual name="visual_mesh">
            <geometry>
                  <mesh>
                    <uri>\(escapeXML(uri))</uri>
                  </mesh>
            </geometry>
            <material>
              <ambient>\(color.diffuseTriple) \(formatA(color.a))</ambient>
              <diffuse>\(color.diffuseTriple) \(formatA(color.a))</diffuse>
              <specular>0.1 0.1 0.1 \(formatA(color.a))</specular>
            </material>
          </visual>
      """
    } else {
      visuals = """
          <visual name="visual">
            <geometry>
                  <box>
                    <size>\(w) \(l) \(h)</size>
                  </box>
            </geometry>
            <material>
              <ambient>\(color.diffuseTriple) \(formatA(color.a))</ambient>
              <diffuse>\(color.diffuseTriple) \(formatA(color.a))</diffuse>
              <specular>0.1 0.1 0.1 \(formatA(color.a))</specular>
            </material>
          </visual>
      """
    }

    return """
    <?xml version="1.0"?>
    <sdf version="1.9">
      <model name="\(escapeXML(modelName))">
        <static>false</static>
        <link name="link">
          <inertial>
            <mass>1.0</mass>
            <inertia>
              <ixx>0.1</ixx><iyy>0.1</iyy><izz>0.1</izz>
            </inertia>
          </inertial>
          <collision name="collision">
            <geometry>
    \(collisionGeometry)
            </geometry>
          </collision>
    \(visuals)
        </link>
      </model>
    </sdf>
    """
  }

  private static func formatM(_ value: Double) -> String {
    value.truncatingRemainder(dividingBy: 1) == 0
      ? String(format: "%.0f", value)
      : String(format: "%.3f", value)
  }

  private static func formatA(_ value: Double) -> String {
    String(format: "%.2f", value)
  }

  private static func escapeXML(_ raw: String) -> String {
    raw
      .replacingOccurrences(of: "&", with: "&amp;")
      .replacingOccurrences(of: "<", with: "&lt;")
      .replacingOccurrences(of: ">", with: "&gt;")
      .replacingOccurrences(of: "\"", with: "&quot;")
  }
}
