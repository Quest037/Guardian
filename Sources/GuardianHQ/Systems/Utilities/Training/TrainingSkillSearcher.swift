import Foundation

/// Generates open-loop segment candidates for autonomous SIM teaching (grid over templates).
enum TrainingSkillSearcher {
    static let defaultMaxTrials = 32

    static func candidates(
        task: TrainingTaskKind,
        layout: TrainingTaskLayout,
        vehicleType: FleetVehicleType,
        forbidden: Set<TrainingControlAxis>,
        maxTrials: Int = defaultMaxTrials
    ) -> [TrainingSkillCandidate] {
        let templates = templateParameterSets(task: task, layout: layout)
        var out: [TrainingSkillCandidate] = []
        var trial = 0
        for params in templates {
            guard trial < maxTrials else { break }
            let segments = buildSegments(
                task: task,
                layout: layout,
                params: params,
                vehicleType: vehicleType,
                forbidden: forbidden
            )
            guard !segments.isEmpty else { continue }
            if segments.contains(where: { segmentViolates($0, vehicleType: vehicleType, forbidden: forbidden) }) {
                continue
            }
            let path = TrainingSkillPathPredictor.predictedPath(start: layout.start, segments: segments)
            out.append(
                TrainingSkillCandidate(
                    trialIndex: trial,
                    segments: segments,
                    summary: params.label,
                    predictedPath: path
                )
            )
            trial += 1
        }
        return out
    }

    /// Perturb the closest trial’s segment speeds/durations for follow-up attempts.
    static func variations(
        around best: TrainingSkillCandidate,
        layout: TrainingTaskLayout,
        vehicleType: FleetVehicleType,
        forbidden: Set<TrainingControlAxis>,
        speedFactors: [Float] = [0.82, 0.92, 1.08, 1.18],
        durationFactors: [Double] = [0.85, 1.0, 1.15]
    ) -> [TrainingSkillCandidate] {
        var out: [TrainingSkillCandidate] = []
        var trial = best.trialIndex + 1_000
        for speedF in speedFactors {
            for durF in durationFactors {
                if speedF == 1, durF == 1 { continue }
                var segments: [TrainingControlSegment] = []
                for seg in best.segments {
                    var next = seg
                    next.bodyForwardMS *= speedF
                    next.bodyRightMS *= speedF
                    next.yawspeedDegS *= speedF
                    next.durationS *= durF
                    segments.append(next)
                }
                if segments.contains(where: { segmentViolates($0, vehicleType: vehicleType, forbidden: forbidden) }) {
                    continue
                }
                let path = TrainingSkillPathPredictor.predictedPath(start: layout.start, segments: segments)
                out.append(
                    TrainingSkillCandidate(
                        trialIndex: trial,
                        segments: segments,
                        summary: String(format: "Refine ×%.2f spd ×%.2f dur", speedF, durF),
                        predictedPath: path
                    )
                )
                trial += 1
            }
        }
        return out
    }

    // MARK: - Templates

    private struct TemplateParams: Equatable {
        let label: String
        let yawRateDegS: Float
        let yawDurationS: Double
        let reverseMS: Float
        let reverseDurationS: Double
        let forwardMS: Float
        let forwardDurationS: Double
        let includeFinalYaw: Bool
    }

    private static func templateParameterSets(
        task: TrainingTaskKind,
        layout: TrainingTaskLayout
    ) -> [TemplateParams] {
        let bearingToGoal = MissionTelemetryGeo.bearingDegrees(
            lat1: layout.start.latitudeDeg,
            lon1: layout.start.longitudeDeg,
            lat2: layout.goal.latitudeDeg,
            lon2: layout.goal.longitudeDeg
        )
        let headingToGoal = MissionTelemetryGeo.angleDifferenceDeg(
            bearingToGoal,
            layout.start.headingDeg
        )
        let yawSign: Float = headingToGoal >= 0 ? 1 : -1
        let headingErrGoal = MissionTelemetryGeo.angleDifferenceDeg(
            layout.goal.headingDeg,
            layout.start.headingDeg
        )

        var params: [TemplateParams] = []
        let yawRates: [Float] = [12, 18, 25]
        let moveSpeeds: [Float] = [0.25, 0.4, 0.55]
        let shortDurations: [Double] = [2, 3.5]
        let moveDurations: [Double] = [3, 5, 7]

        switch task {
        case .reverseIntoSlot:
            for yawRate in yawRates {
                for reverseMS in moveSpeeds {
                    for reverseDur in moveDurations {
                        for yawDur in shortDurations {
                            params.append(
                                TemplateParams(
                                    label: String(
                                        format: "Yaw %.0f°/s %.1fs → reverse %.2f m/s %.1fs → yaw goal",
                                        yawRate * yawSign,
                                        yawDur,
                                        reverseMS,
                                        reverseDur
                                    ),
                                    yawRateDegS: yawRate * yawSign,
                                    yawDurationS: yawDur,
                                    reverseMS: reverseMS,
                                    reverseDurationS: reverseDur,
                                    forwardMS: 0,
                                    forwardDurationS: 0,
                                    includeFinalYaw: true
                                )
                            )
                        }
                    }
                }
            }
        case .approachSlotForward:
            for yawRate in yawRates {
                for fwdMS in moveSpeeds {
                    for fwdDur in moveDurations {
                        params.append(
                            TemplateParams(
                                label: String(
                                    format: "Yaw %.0f°/s %.1fs → forward %.2f m/s %.1fs",
                                    yawRate * yawSign,
                                    shortDurations[0],
                                    fwdMS,
                                    fwdDur
                                ),
                                yawRateDegS: yawRate * yawSign,
                                yawDurationS: shortDurations[0],
                                reverseMS: 0,
                                reverseDurationS: 0,
                                forwardMS: fwdMS,
                                forwardDurationS: fwdDur,
                                includeFinalYaw: true
                            )
                        )
                    }
                }
            }
        case .alignHeadingAtSlot:
            for yawRate in yawRates {
                for reverseMS in [Float(0.2), 0.35] {
                    for reverseDur in [2.5, 4] {
                        for fwdMS in [Float(0.22), 0.35] {
                            params.append(
                                TemplateParams(
                                    label: String(
                                        format: "3-point micro: rev %.2f %.1fs → fwd %.2f %.1fs",
                                        reverseMS,
                                        reverseDur,
                                        fwdMS,
                                        shortDurations[1]
                                    ),
                                    yawRateDegS: yawRate * (headingErrGoal >= 0 ? 1 : -1),
                                    yawDurationS: 1.5,
                                    reverseMS: reverseMS,
                                    reverseDurationS: reverseDur,
                                    forwardMS: fwdMS,
                                    forwardDurationS: shortDurations[1],
                                    includeFinalYaw: true
                                )
                            )
                        }
                    }
                }
            }
        }
        return params
    }

    private static func buildSegments(
        task: TrainingTaskKind,
        layout: TrainingTaskLayout,
        params: TemplateParams,
        vehicleType: FleetVehicleType,
        forbidden: Set<TrainingControlAxis>
    ) -> [TrainingControlSegment] {
        var segments: [TrainingControlSegment] = []
        let settle = TrainingControlSegment.hold(durationS: 0.4)

        if abs(params.yawRateDegS) > 0.5, mayUseYaw(rate: params.yawRateDegS, forbidden: forbidden) {
            segments.append(.yaw(params.yawRateDegS, durationS: params.yawDurationS))
            segments.append(settle)
        }

        switch task {
        case .reverseIntoSlot:
            if params.reverseMS > 0, !forbidden.contains(.driveReverse) {
                segments.append(.reverse(params.reverseMS, durationS: params.reverseDurationS))
                segments.append(settle)
            }
        case .approachSlotForward:
            if params.forwardMS > 0, !forbidden.contains(.driveForward) {
                segments.append(.forward(params.forwardMS, durationS: params.forwardDurationS))
                segments.append(settle)
            }
        case .alignHeadingAtSlot:
            if params.reverseMS > 0, !forbidden.contains(.driveReverse) {
                segments.append(.reverse(params.reverseMS, durationS: params.reverseDurationS))
                segments.append(settle)
            }
            if params.forwardMS > 0, !forbidden.contains(.driveForward) {
                segments.append(.forward(params.forwardMS, durationS: params.forwardDurationS))
                segments.append(settle)
            }
        }

        if params.includeFinalYaw {
            let err = MissionTelemetryGeo.angleDifferenceDeg(
                layout.goal.headingDeg,
                layout.start.headingDeg
            )
            let rate: Float = err >= 0 ? abs(params.yawRateDegS) : -abs(params.yawRateDegS)
            if abs(rate) > 0.5, mayUseYaw(rate: rate, forbidden: forbidden) {
                segments.append(.yaw(rate, durationS: max(1.5, params.yawDurationS)))
            }
        }

        return segments.filter { $0.durationS > 0 }
    }

    private static func mayUseYaw(rate: Float, forbidden: Set<TrainingControlAxis>) -> Bool {
        if rate > 0.5 { return !forbidden.contains(.turnClockwise) }
        if rate < -0.5 { return !forbidden.contains(.turnCounterClockwise) }
        return true
    }

    private static func segmentViolates(
        _ segment: TrainingControlSegment,
        vehicleType: FleetVehicleType,
        forbidden: Set<TrainingControlAxis>
    ) -> Bool {
        !TrainingVehicleControlCapabilities.validateSegment(segment, vehicleType: vehicleType, forbidden: forbidden)
            .isEmpty
    }
}
