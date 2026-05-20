import Foundation

/// Bakes ``TrainingEnvironmentManifest/obstacles`` into one static Gazebo model for Training `.run` worlds.
enum TrainingEnvironmentObstacleBaking {
    static let bakedModelName = "guardian_obstacles_baked"
    static let bakedVisualOBJFileName = "guardian_obstacles_baked.obj"

    /// One `<model>` block: compound collisions + single merged visual mesh.
    static func bakedModelXML(
        records: [TrainingEnvironmentObstacleRecord],
        meshDirectory: URL
    ) throws -> String {
        guard !records.isEmpty else { return "" }
        try FileManager.default.createDirectory(at: meshDirectory, withIntermediateDirectories: true)
        let visualURI = try writeMergedVisualOBJ(records: records, meshDirectory: meshDirectory)
        var collisionBlocks: [String] = []
        for (index, record) in records.enumerated() {
            collisionBlocks.append(
                try TrainingEnvironmentObstacleSDF.bakedCollisionElement(
                    record: record,
                    index: index,
                    meshDirectory: meshDirectory
                )
            )
        }
        let collisions = collisionBlocks.joined(separator: "\n")
        return """
            <model name="\(escapeXML(bakedModelName))">
              <static>true</static>
              <pose>0 0 0 0 0 0</pose>
              <link name="link">
        \(collisions)
                <visual name="visual">
                  <geometry>
                    <mesh>
                      <uri>\(escapeXML(visualURI.absoluteString))</uri>
                    </mesh>
                  </geometry>
                  <material>
                    <ambient>\(TrainingEnvironmentObstacleSDF.greyAmbient) 1</ambient>
                    <diffuse>\(TrainingEnvironmentObstacleSDF.greyDiffuse) 1</diffuse>
                    <specular>0.08 0.08 0.08 1</specular>
                  </material>
                </visual>
              </link>
            </model>
        """
    }

    static func isBakedObstacleModelName(_ name: String) -> Bool {
        name == bakedModelName
    }

    static func pruneLegacyAuthoringMeshes(in meshDirectory: URL) throws {
        let fm = FileManager.default
        guard fm.fileExists(atPath: meshDirectory.path) else { return }
        let entries = try fm.contentsOfDirectory(at: meshDirectory, includingPropertiesForKeys: nil)
        for url in entries {
            let name = url.lastPathComponent
            if name == bakedVisualOBJFileName { continue }
            if name.hasPrefix(TrainingEnvironmentObstacleNaming.modelPrefix)
                || name.hasSuffix(".obj")
                || name.hasSuffix(".sdf") {
                try fm.removeItem(at: url)
            }
        }
    }

    private static func writeMergedVisualOBJ(
        records: [TrainingEnvironmentObstacleRecord],
        meshDirectory: URL
    ) throws -> URL {
        var builder = MergedObstacleOBJBuilder()
        for record in records {
            builder.append(record: record)
        }
        let url = meshDirectory.appendingPathComponent(bakedVisualOBJFileName)
        try builder.write(to: url)
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

// MARK: - Merged OBJ

private struct MergedObstacleOBJBuilder {
    private(set) var vertices: [(Double, Double, Double)] = []
    private var faces: [[Int]] = []

    mutating func append(record: TrainingEnvironmentObstacleRecord) {
        let yawRad = record.yawDeg * .pi / 180
        switch record.kind {
        case .cube:
            let edge = max(record.cube?.edgeM ?? 2, 0.01)
            appendBox(center: record.center, yawRad: yawRad, dx: edge, dy: edge, dz: edge)
        case .cuboid:
            let c = record.cuboid ?? TrainingObstacleCuboid(lengthM: 2, widthM: 2, heightM: 2)
            appendBox(
                center: record.center,
                yawRad: yawRad,
                dx: max(c.lengthM, 0.01),
                dy: max(c.widthM, 0.01),
                dz: max(c.heightM, 0.01)
            )
        case .cylinder:
            let c = record.cylinder ?? TrainingObstacleCylinder(radiusM: 1, heightM: 2)
            if record.axisOrientation == .horizontal {
                appendHorizontalCylinder(
                    center: record.center,
                    yawRad: yawRad,
                    radius: max(c.radiusM, 0.01),
                    length: max(c.heightM, 0.01)
                )
            } else {
                appendVerticalCylinder(
                    center: record.center,
                    yawRad: yawRad,
                    radius: max(c.radiusM, 0.01),
                    height: max(c.heightM, 0.01)
                )
            }
        case .cone:
            let c = record.cone ?? TrainingObstacleCone(radiusM: 1, heightM: 2)
            appendCone(
                center: record.center,
                yawRad: yawRad,
                radius: max(c.radiusM, 0.01),
                height: max(c.heightM, 0.01)
            )
        case .pyramid:
            let p = record.pyramid ?? TrainingObstaclePyramid(baseWidthM: 2, baseDepthM: 2, heightM: 2)
            appendPyramid(
                center: record.center,
                yawRad: yawRad,
                width: max(p.baseWidthM, 0.01),
                depth: max(p.baseDepthM, 0.01),
                height: max(p.heightM, 0.01)
            )
        case .toblerone:
            let t = record.toblerone ?? TrainingObstacleToblerone(widthM: 2, lengthM: 2)
            if record.axisOrientation == .horizontal {
                appendTobleroneHorizontal(
                    center: record.center,
                    yawRad: yawRad,
                    width: max(t.widthM, 0.01),
                    length: max(t.lengthM, 0.01)
                )
            } else {
                appendTobleroneVertical(
                    center: record.center,
                    yawRad: yawRad,
                    width: max(t.widthM, 0.01),
                    length: max(t.lengthM, 0.01)
                )
            }
        }
    }

    func write(to url: URL) throws {
        var lines = ["# Guardian baked obstacles"]
        for vertex in vertices {
            lines.append(String(format: "v %.6f %.6f %.6f", vertex.0, vertex.1, vertex.2))
        }
        for face in faces {
            lines.append("f" + face.map { " \($0)" }.joined())
        }
        try lines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
    }

    private mutating func appendBox(
        center: (Double, Double, Double),
        yawRad: Double,
        dx: Double,
        dy: Double,
        dz: Double
    ) {
        let hx = dx / 2
        let hy = dy / 2
        let hz = dz / 2
        let locals: [(Double, Double, Double)] = [
            (-hx, -hy, -hz), (hx, -hy, -hz), (hx, hy, -hz), (-hx, hy, -hz),
            (-hx, -hy, hz), (hx, -hy, hz), (hx, hy, hz), (-hx, hy, hz),
        ]
        let base = vertices.count
        for local in locals {
            vertices.append(transform(local, center: center, yawRad: yawRad))
        }
        let quads = [
            [1, 2, 3, 4], [5, 6, 7, 8], [1, 2, 6, 5], [2, 3, 7, 6],
            [3, 4, 8, 7], [4, 1, 5, 8],
        ]
        for quad in quads {
            faces.append(quad.map { base + $0 })
        }
    }

    private mutating func appendVerticalCylinder(
        center: (Double, Double, Double),
        yawRad: Double,
        radius: Double,
        height: Double
    ) {
        appendPrism(
            center: center,
            yawRad: yawRad,
            localPoints: cylinderProfile(radius: radius, height: height, horizontal: false),
            capCenterIndices: (bottom: 0, top: 1)
        )
    }

    private mutating func appendHorizontalCylinder(
        center: (Double, Double, Double),
        yawRad: Double,
        radius: Double,
        length: Double
    ) {
        appendPrism(
            center: center,
            yawRad: yawRad,
            localPoints: cylinderProfile(radius: radius, height: length, horizontal: true),
            capCenterIndices: (bottom: 0, top: 1)
        )
    }

    private mutating func appendCone(
        center: (Double, Double, Double),
        yawRad: Double,
        radius: Double,
        height: Double
    ) {
        let segments = 16
        var locals: [(Double, Double, Double)] = [(0, 0, -height / 2)]
        for index in 0..<segments {
            let angle = 2 * Double.pi * Double(index) / Double(segments)
            locals.append((
                radius * cos(angle),
                radius * sin(angle),
                -height / 2
            ))
        }
        locals.append((0, 0, height / 2))
        let apex = locals.count
        let base = vertices.count
        for local in locals {
            vertices.append(transform(local, center: center, yawRad: yawRad))
        }
        for index in 0..<segments {
            let a = base + 1 + index
            let b = base + 1 + ((index + 1) % segments)
            faces.append([a, b, base + apex])
            faces.append([b, a, base + 1])
        }
    }

    private mutating func appendPyramid(
        center: (Double, Double, Double),
        yawRad: Double,
        width: Double,
        depth: Double,
        height: Double
    ) {
        let hw = width / 2
        let hd = depth / 2
        let apex = height / 2
        let baseZ = -height / 2
        let locals: [(Double, Double, Double)] = [
            (-hw, -hd, baseZ), (hw, -hd, baseZ), (hw, hd, baseZ), (-hw, hd, baseZ),
            (0, 0, apex),
        ]
        let faceLoops = [
            [1, 2, 5], [2, 3, 5], [3, 4, 5], [4, 1, 5],
            [1, 4, 3], [1, 3, 2],
        ]
        let base = vertices.count
        for local in locals {
            vertices.append(transform(local, center: center, yawRad: yawRad))
        }
        for loop in faceLoops {
            faces.append(loop.map { base + $0 })
        }
    }

    private mutating func appendTobleroneVertical(
        center: (Double, Double, Double),
        yawRad: Double,
        width: Double,
        length: Double
    ) {
        let locals = tobleroneVertices(width: width, length: length, horizontal: false)
        appendPolyhedron(center: center, yawRad: yawRad, locals: locals, faces: tobleroneFaces())
    }

    private mutating func appendTobleroneHorizontal(
        center: (Double, Double, Double),
        yawRad: Double,
        width: Double,
        length: Double
    ) {
        let locals = tobleroneVertices(width: width, length: length, horizontal: true)
        appendPolyhedron(center: center, yawRad: yawRad, locals: locals, faces: tobleroneFaces())
    }

    private mutating func appendPrism(
        center: (Double, Double, Double),
        yawRad: Double,
        localPoints: [(center: (Double, Double, Double), ring: [(Double, Double, Double)])],
        capCenterIndices: (bottom: Int, top: Int)
    ) {
        let base = vertices.count
        var allLocals: [(Double, Double, Double)] = [localPoints[capCenterIndices.bottom].center]
        allLocals.append(contentsOf: localPoints[capCenterIndices.bottom].ring)
        allLocals.append(localPoints[capCenterIndices.top].center)
        let topCenter = allLocals.count
        allLocals.append(localPoints[capCenterIndices.top].center)
        let topRingStart = topCenter + 1
        allLocals.append(contentsOf: localPoints[capCenterIndices.top].ring)

        for local in allLocals {
            vertices.append(transform(local, center: center, yawRad: yawRad))
        }
        let segments = localPoints[capCenterIndices.bottom].ring.count
        for index in 0..<segments {
            let b0 = base + 1 + index
            let b1 = base + 1 + ((index + 1) % segments)
            let t0 = base + topRingStart + index
            let t1 = base + topRingStart + ((index + 1) % segments)
            faces.append([b0, b1, t1])
            faces.append([b0, t1, t0])
        }
    }

    private mutating func appendPolyhedron(
        center: (Double, Double, Double),
        yawRad: Double,
        locals: [(Double, Double, Double)],
        faces faceLoops: [[Int]]
    ) {
        let base = vertices.count
        for local in locals {
            vertices.append(transform(local, center: center, yawRad: yawRad))
        }
        for loop in faceLoops {
            faces.append(loop.map { base + $0 })
        }
    }

    private func cylinderProfile(
        radius: Double,
        height: Double,
        horizontal: Bool
    ) -> [(center: (Double, Double, Double), ring: [(Double, Double, Double)])] {
        let segments = 16
        var bottomRing: [(Double, Double, Double)] = []
        var topRing: [(Double, Double, Double)] = []
        for index in 0..<segments {
            let angle = 2 * Double.pi * Double(index) / Double(segments)
            let x = radius * cos(angle)
            let y = radius * sin(angle)
            if horizontal {
                bottomRing.append((-height / 2, x, y))
                topRing.append((height / 2, x, y))
            } else {
                bottomRing.append((x, y, -height / 2))
                topRing.append((x, y, height / 2))
            }
        }
        let bottomCenter = horizontal ? (-height / 2, 0.0, 0.0) : (0.0, 0.0, -height / 2)
        let topCenter = horizontal ? (height / 2, 0.0, 0.0) : (0.0, 0.0, height / 2)
        return [(bottomCenter, bottomRing), (topCenter, topRing)]
    }

    private func tobleroneVertices(
        width: Double,
        length: Double,
        horizontal: Bool
    ) -> [(Double, Double, Double)] {
        let triH = width * sqrt(3) / 2
        let halfL = length / 2
        if horizontal {
            return [
                (-width / 2, -triH / 3, -halfL), (width / 2, -triH / 3, -halfL), (0, 2 * triH / 3, -halfL),
                (-width / 2, -triH / 3, halfL), (width / 2, -triH / 3, halfL), (0, 2 * triH / 3, halfL),
            ]
        }
        return [
            (-width / 2, -triH / 3, -halfL), (width / 2, -triH / 3, -halfL), (0, 2 * triH / 3, -halfL),
            (-width / 2, -triH / 3, halfL), (width / 2, -triH / 3, halfL), (0, 2 * triH / 3, halfL),
        ]
    }

    private func tobleroneFaces() -> [[Int]] {
        [
            [1, 2, 3], [4, 6, 5],
            [1, 4, 5], [1, 5, 2],
            [2, 5, 6], [2, 6, 3],
            [3, 6, 4], [3, 4, 1],
        ]
    }

    private func transform(
        _ local: (Double, Double, Double),
        center: (Double, Double, Double),
        yawRad: Double
    ) -> (Double, Double, Double) {
        let c = cos(yawRad)
        let s = sin(yawRad)
        let x = local.0 * c - local.1 * s
        let y = local.0 * s + local.1 * c
        return (center.0 + x, center.1 + y, center.2 + local.2)
    }
}

private extension TrainingEnvironmentObstacleRecord {
    var center: (Double, Double, Double) {
        (centerXM, centerYM, centerZM)
    }
}
