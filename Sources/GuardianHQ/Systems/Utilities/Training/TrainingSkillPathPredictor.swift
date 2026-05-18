import Foundation

/// Dead-reckoning preview of where open-loop training segments should end (map dashed path).
enum TrainingSkillPathPredictor {
    private static let integrationStepS = 0.25

    static func predictedPath(
        start: TrainingTaskPose,
        segments: [TrainingControlSegment]
    ) -> [RouteCoordinate] {
        var lat = start.latitudeDeg
        var lon = start.longitudeDeg
        var headingDeg = start.headingDeg
        var points: [RouteCoordinate] = [RouteCoordinate(lat: lat, lon: lon)]

        for segment in segments {
            let duration = max(0, segment.durationS)
            guard duration > 0 else { continue }
            let steps = max(1, Int(ceil(duration / integrationStepS)))
            let subDt = duration / Double(steps)
            for _ in 0..<steps {
                headingDeg += Double(segment.yawspeedDegS) * subDt
                let forwardM = Double(segment.bodyForwardMS) * subDt
                let rightM = Double(segment.bodyRightMS) * subDt
                let offset = MissionSquadFormationGeometry.offsetCoordinate(
                    latitudeDeg: lat,
                    longitudeDeg: lon,
                    headingDeg: headingDeg,
                    forwardMeters: forwardM,
                    rightMeters: rightM
                )
                lat = offset.lat
                lon = offset.lon
                points.append(RouteCoordinate(lat: lat, lon: lon))
            }
        }
        return points
    }

    static func predictedEndpoint(
        start: TrainingTaskPose,
        segments: [TrainingControlSegment]
    ) -> TrainingTaskPose {
        let path = predictedPath(start: start, segments: segments)
        let last = path.last ?? RouteCoordinate(lat: start.latitudeDeg, lon: start.longitudeDeg)
        var heading = start.headingDeg
        for segment in segments {
            heading += Double(segment.yawspeedDegS) * segment.durationS
        }
        return TrainingTaskPose(
            latitudeDeg: last.lat,
            longitudeDeg: last.lon,
            headingDeg: heading,
            absoluteAltitudeM: start.absoluteAltitudeM
        )
    }
}
