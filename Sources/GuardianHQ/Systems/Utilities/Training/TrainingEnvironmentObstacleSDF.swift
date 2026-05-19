import Foundation

/// SDFormat static models for World Builder obstacles (collision + grey visual).
enum TrainingEnvironmentObstacleSDF {
    static let greyAmbient = "0.45 0.45 0.45"
    static let greyDiffuse = "0.55 0.55 0.55"

    /// One collision primitive for ``TrainingEnvironmentObstacleBaking`` (world-space pose on the baked link).
    static func bakedCollisionElement(
        record: TrainingEnvironmentObstacleRecord,
        index: Int,
        meshDirectory: URL
    ) throws -> String {
        let yawRad = record.yawDeg * .pi / 180
        let (geometryXML, meshPoseOffset) = try geometryXML(record: record, meshDirectory: meshDirectory)
        var roll = 0.0
        var pitch = 0.0
        var yaw = yawRad
        if !meshPoseOffset.isEmpty {
            let parts = meshPoseOffset.split(separator: " ").compactMap { Double($0) }
            if parts.count >= 6 {
                roll += parts[3]
                pitch += parts[4]
                yaw += parts[5]
            }
        }
        let pose = String(
            format: "%.4f %.4f %.4f %.4f %.4f %.4f",
            record.centerXM,
            record.centerYM,
            record.centerZM,
            roll,
            pitch,
            yaw
        )
        return """
                <collision name="collision_\(index)">
                  <pose>\(pose)</pose>
                  <geometry>
        \(geometryXML)
                  </geometry>
                </collision>
        """
    }

    struct WrittenObstacleModel: Equatable, Sendable {
        let modelName: String
        let sdfURL: URL
    }

    /// Single-model SDF for `gz service` `/world/.../create` (live insert without restarting sim).
    static func writeTemporaryModel(
        record: TrainingEnvironmentObstacleRecord,
        meshDirectory: URL
    ) throws -> WrittenObstacleModel {
        try FileManager.default.createDirectory(at: meshDirectory, withIntermediateDirectories: true)
        let name = record.gazeboModelName
        let (geometryXML, meshPoseOffset) = try geometryXML(record: record, meshDirectory: meshDirectory)
        let linkPose = meshPoseOffset.isEmpty ? "" : "      <pose>\(meshPoseOffset)</pose>\n"
        let xml = """
        <?xml version="1.0" ?>
        <sdf version="1.9">
          <model name="\(escapeXML(name))">
            <static>true</static>
            <link name="link">
        \(linkPose)        <collision name="collision">
                <geometry>
        \(geometryXML)
                </geometry>
              </collision>
              <visual name="visual">
                <geometry>
        \(geometryXML)
                </geometry>
                <material>
                  <ambient>\(greyAmbient) 1</ambient>
                  <diffuse>\(greyDiffuse) 1</diffuse>
                  <specular>0.08 0.08 0.08 1</specular>
                </material>
              </visual>
            </link>
          </model>
        </sdf>
        """
        let sdfURL = meshDirectory.appendingPathComponent("\(name).sdf")
        try xml.write(to: sdfURL, atomically: true, encoding: .utf8)
        return WrittenObstacleModel(modelName: name, sdfURL: sdfURL)
    }

    static func obstacleModelsXML(
        records: [TrainingEnvironmentObstacleRecord],
        meshDirectory: URL
    ) throws -> String {
        try FileManager.default.createDirectory(at: meshDirectory, withIntermediateDirectories: true)
        var blocks: [String] = []
        for record in records.prefix(TrainingEnvironmentObstacleRecord.maxCount) {
            blocks.append(try modelXML(record: record, meshDirectory: meshDirectory))
        }
        return blocks.joined(separator: "\n")
    }

    private static func modelXML(
        record: TrainingEnvironmentObstacleRecord,
        meshDirectory: URL
    ) throws -> String {
        let name = record.gazeboModelName
        let yawRad = record.yawDeg * .pi / 180
        let pose = String(
            format: "%.4f %.4f %.4f 0 0 %.4f",
            record.centerXM,
            record.centerYM,
            record.centerZM,
            yawRad
        )
        let (geometryXML, meshPoseOffset) = try geometryXML(record: record, meshDirectory: meshDirectory)
        let linkPose = meshPoseOffset.isEmpty ? "" : "      <pose>\(meshPoseOffset)</pose>\n"
        return """
            <model name="\(escapeXML(name))">
              <static>true</static>
              <pose>\(pose)</pose>
              <link name="link">
        \(linkPose)        <collision name="collision">
                  <geometry>
        \(geometryXML)
                  </geometry>
                </collision>
                <visual name="visual">
                  <geometry>
        \(geometryXML)
                  </geometry>
                  <material>
                    <ambient>\(greyAmbient) 1</ambient>
                    <diffuse>\(greyDiffuse) 1</diffuse>
                    <specular>0.08 0.08 0.08 1</specular>
                  </material>
                </visual>
              </link>
            </model>
        """
    }

    private static func geometryXML(
        record: TrainingEnvironmentObstacleRecord,
        meshDirectory: URL
    ) throws -> (xml: String, linkPoseOffset: String) {
        let fmt3: (Double, Double, Double) -> String = { a, b, c in
            String(format: "%.4f %.4f %.4f", a, b, c)
        }
        switch record.kind {
        case .cube:
            let edge = max(record.cube?.edgeM ?? 2, 0.01)
            return (boxXML(size: fmt3(edge, edge, edge)), "")
        case .cuboid:
            let c = record.cuboid ?? TrainingObstacleCuboid(lengthM: 2, widthM: 2, heightM: 2)
            return (
                boxXML(size: fmt3(c.lengthM, c.widthM, c.heightM)),
                ""
            )
        case .cylinder:
            let c = record.cylinder ?? TrainingObstacleCylinder(radiusM: 1, heightM: 2)
            if record.axisOrientation == .horizontal {
                return (
                    cylinderXML(radius: c.radiusM, length: c.heightM),
                    "0 0 0 0 1.57079632679 0"
                )
            }
            return (cylinderXML(radius: c.radiusM, length: c.heightM), "")
        case .cone:
            let c = record.cone ?? TrainingObstacleCone(radiusM: 1, heightM: 2)
            return (coneXML(radius: c.radiusM, length: c.heightM), "")
        case .pyramid:
            let p = record.pyramid ?? TrainingObstaclePyramid(baseWidthM: 2, baseDepthM: 2, heightM: 2)
            let meshURL = try writePyramidMesh(
                id: record.id,
                width: p.baseWidthM,
                depth: p.baseDepthM,
                height: p.heightM,
                meshDirectory: meshDirectory
            )
            return (meshXML(uri: meshURL), "")
        case .toblerone:
            let t = record.toblerone ?? TrainingObstacleToblerone(widthM: 2, lengthM: 2)
            let meshURL = try writeTobleroneMesh(
                id: record.id,
                width: t.widthM,
                length: t.lengthM,
                meshDirectory: meshDirectory
            )
            if record.axisOrientation == .horizontal {
                return (meshXML(uri: meshURL), "0 0 0 1.57079632679 0 0")
            }
            return (meshXML(uri: meshURL), "")
        }
    }

    private static func boxXML(size: String) -> String {
        """
                    <box>
                      <size>\(size)</size>
                    </box>
        """
    }

    private static func cylinderXML(radius: Double, length: Double) -> String {
        let r = max(radius, 0.01)
        let l = max(length, 0.01)
        return """
                    <cylinder>
                      <radius>\(String(format: "%.4f", r))</radius>
                      <length>\(String(format: "%.4f", l))</length>
                    </cylinder>
        """
    }

    private static func coneXML(radius: Double, length: Double) -> String {
        let r = max(radius, 0.01)
        let l = max(length, 0.01)
        return """
                    <cone>
                      <radius>\(String(format: "%.4f", r))</radius>
                      <length>\(String(format: "%.4f", l))</length>
                    </cone>
        """
    }

    private static func meshXML(uri: URL) -> String {
        """
                    <mesh>
                      <uri>\(escapeXML(uri.absoluteString))</uri>
                    </mesh>
        """
    }

    private static func writePyramidMesh(
        id: String,
        width: Double,
        depth: Double,
        height: Double,
        meshDirectory: URL
    ) throws -> URL {
        let w = max(width, 0.01)
        let d = max(depth, 0.01)
        let h = max(height, 0.01)
        let hw = w / 2
        let hd = d / 2
        let apex = h / 2
        let base = -h / 2
        let vertices: [(Double, Double, Double)] = [
            (-hw, -hd, base), (hw, -hd, base), (hw, hd, base), (-hw, hd, base),
            (0, 0, apex),
        ]
        let faces = [
            [1, 2, 5], [2, 3, 5], [3, 4, 5], [4, 1, 5],
            [1, 4, 3], [1, 3, 2],
        ]
        return try writeOBJ(id: id, suffix: "pyramid", vertices: vertices, faces: faces, meshDirectory: meshDirectory)
    }

    private static func writeTobleroneMesh(
        id: String,
        width: Double,
        length: Double,
        meshDirectory: URL
    ) throws -> URL {
        let w = max(width, 0.01)
        let l = max(length, 0.01)
        let triH = w * sqrt(3) / 2
        let halfL = l / 2
        let vertices: [(Double, Double, Double)] = [
            (-w / 2, -triH / 3, -halfL),
            (w / 2, -triH / 3, -halfL),
            (0, 2 * triH / 3, -halfL),
            (-w / 2, -triH / 3, halfL),
            (w / 2, -triH / 3, halfL),
            (0, 2 * triH / 3, halfL),
        ]
        let faces = [
            [1, 2, 3], [4, 6, 5],
            [1, 4, 5], [1, 5, 2],
            [2, 5, 6], [2, 6, 3],
            [3, 6, 4], [3, 4, 1],
        ]
        return try writeOBJ(id: id, suffix: "toblerone", vertices: vertices, faces: faces, meshDirectory: meshDirectory)
    }

    private static func writeOBJ(
        id: String,
        suffix: String,
        vertices: [(Double, Double, Double)],
        faces: [[Int]],
        meshDirectory: URL
    ) throws -> URL {
        let safe = id.replacingOccurrences(of: "-", with: "_")
        let url = meshDirectory.appendingPathComponent("\(safe)_\(suffix).obj")
        var lines = ["# Guardian obstacle mesh"]
        for vertex in vertices {
            lines.append(String(format: "v %.6f %.6f %.6f", vertex.0, vertex.1, vertex.2))
        }
        for face in faces {
            let indices = face.map { " \($0)" }.joined()
            lines.append("f\(indices)")
        }
        try lines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    private static func escapeXML(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
}
