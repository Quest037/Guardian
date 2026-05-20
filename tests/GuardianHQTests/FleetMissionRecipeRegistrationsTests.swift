import XCTest
@testable import GuardianCore

@MainActor
final class FleetMissionRecipeRegistrationsTests: XCTestCase {

    override func setUp() async throws {
        try await super.setUp()
        FleetRecipesCatalogue.shared._testOnlyReset()
        FleetRecipesCatalogueBootstrap._testOnlyResetIdempotencyFlag()
        FleetCommandsCatalogueBootstrap.ensureRegistered()
    }

    func test_registerAll_registersDoMissionUploadStart() {
        FleetMissionRecipeRegistrations.registerAll()

        let name = FleetMissionRecipeRegistrations.doMissionUploadStartRecipeName
        let descriptor = FleetRecipesCatalogue.shared.descriptor(for: name)
        XCTAssertNotNil(descriptor)
        XCTAssertEqual(descriptor?.riskTier, .confirmInLiveMission)
        XCTAssertEqual(descriptor?.appliesToSystems, ["mission"])
        XCTAssertEqual(descriptor?.parameters.count, 2)
        XCTAssertEqual(
            Set(descriptor?.parameters.map(\.name) ?? []),
            ["missionItemsJSON", "geofencePolygonsJSON"]
        )

        let body = descriptor?.body
        XCTAssertEqual(body?.entryStepID.rawValue, "upload")
        XCTAssertEqual(body?.steps.count, 3)
        XCTAssertEqual(body?.steps.map(\.id.rawValue), ["upload", "arm", "start"])

        guard let descriptor else { return }
        guard let body = descriptor.body else {
            return XCTFail("Mission upload/start recipe descriptor must carry a body")
        }
        let parseErrors = FleetRecipeBodyParser.validate(
            body,
            against: descriptor,
            recipes: FleetRecipesCatalogue.shared,
            commands: FleetCommandsCatalogue.shared
        )
        XCTAssertTrue(
            parseErrors.isEmpty,
            "Mission upload/start recipe body must validate (bundle JSON or compiled-in): \(parseErrors)"
        )
    }

    func test_registerAll_registersDoMissionUploadStartItem() {
        FleetMissionRecipeRegistrations.registerAll()

        let name = FleetMissionRecipeRegistrations.doMissionUploadStartItemRecipeName
        let descriptor = FleetRecipesCatalogue.shared.descriptor(for: name)
        XCTAssertNotNil(descriptor)
        XCTAssertEqual(descriptor?.riskTier, .confirmInLiveMission)
        XCTAssertEqual(descriptor?.appliesToSystems, ["mission"])
        XCTAssertEqual(descriptor?.parameters.count, 3)
        XCTAssertEqual(
            Set(descriptor?.parameters.map(\.name) ?? []),
            ["missionItemsJSON", "missionStartItemIndex", "geofencePolygonsJSON"]
        )

        let body = descriptor?.body
        XCTAssertEqual(body?.entryStepID.rawValue, "upload")
        XCTAssertEqual(body?.steps.count, 4)
        XCTAssertEqual(body?.steps.map(\.id.rawValue), ["upload", "setMissionItem", "arm", "start"])

        guard let descriptor else { return }
        guard let body = descriptor.body else {
            return XCTFail("Mission upload/start.item recipe descriptor must carry a body")
        }
        let parseErrors = FleetRecipeBodyParser.validate(
            body,
            against: descriptor,
            recipes: FleetRecipesCatalogue.shared,
            commands: FleetCommandsCatalogue.shared
        )
        XCTAssertTrue(
            parseErrors.isEmpty,
            "Mission upload/start.item recipe body must validate (bundle JSON or compiled-in): \(parseErrors)"
        )
    }

    func test_registerAll_registersGeofenceRecipes() {
        FleetMissionRecipeRegistrations.registerAll()

        let upload = FleetRecipesCatalogue.shared.descriptor(for: FleetMissionRecipeRegistrations.doGeofenceUploadRecipeName)
        XCTAssertNotNil(upload)
        XCTAssertEqual(upload?.parameters.count, 1)
        XCTAssertEqual(upload?.parameters.first?.name, "geofencePolygonsJSON")

        let clear = FleetRecipesCatalogue.shared.descriptor(for: FleetMissionRecipeRegistrations.doGeofenceClearRecipeName)
        XCTAssertNotNil(clear)
        XCTAssertTrue(clear?.parameters.isEmpty ?? false)

        guard let upload, let clear, let uploadBody = upload.body, let clearBody = clear.body else {
            return XCTFail("geofence recipes must carry bodies")
        }
        XCTAssertTrue(
            FleetRecipeBodyParser.validate(
                uploadBody,
                against: upload,
                recipes: FleetRecipesCatalogue.shared,
                commands: FleetCommandsCatalogue.shared
            ).isEmpty
        )
        XCTAssertTrue(
            FleetRecipeBodyParser.validate(
                clearBody,
                against: clear,
                recipes: FleetRecipesCatalogue.shared,
                commands: FleetCommandsCatalogue.shared
            ).isEmpty
        )
    }

    func test_registerAll_registersDoReturnHome() {
        FleetMissionRecipeRegistrations.registerAll()

        let name = FleetMissionRecipeRegistrations.doReturnHomeRecipeName
        let descriptor = FleetRecipesCatalogue.shared.descriptor(for: name)
        XCTAssertNotNil(descriptor)
        XCTAssertEqual(descriptor?.riskTier, .confirmInLiveMission)
        XCTAssertEqual(descriptor?.appliesToSystems, ["mission"])
        XCTAssertTrue(descriptor?.parameters.isEmpty ?? false)

        let body = descriptor?.body
        XCTAssertEqual(body?.entryStepID.rawValue, "returnHome")
        XCTAssertEqual(body?.steps.count, 1)
        XCTAssertEqual(body?.steps.map(\.id.rawValue), ["returnHome"])

        guard let descriptor else { return }
        guard let body = descriptor.body else {
            return XCTFail("Return-home recipe descriptor must carry a body")
        }
        let parseErrors = FleetRecipeBodyParser.validate(
            body,
            against: descriptor,
            recipes: FleetRecipesCatalogue.shared,
            commands: FleetCommandsCatalogue.shared
        )
        XCTAssertTrue(
            parseErrors.isEmpty,
            "Return-home recipe body must validate (bundle JSON or compiled-in): \(parseErrors)"
        )
    }

    func test_registerAll_registersVehicleDoPark() {
        FleetMissionRecipeRegistrations.registerAll()

        let name = FleetMissionRecipeRegistrations.vehicleDoParkRecipeName
        let descriptor = FleetRecipesCatalogue.shared.descriptor(for: name)
        XCTAssertNotNil(descriptor)
        XCTAssertEqual(descriptor?.riskTier, .confirmInLiveMission)
        XCTAssertEqual(descriptor?.appliesToSystems, ["mission"])
        XCTAssertTrue(descriptor?.parameters.isEmpty ?? false)

        let body = descriptor?.body
        XCTAssertEqual(body?.entryStepID.rawValue, "park")
        XCTAssertEqual(body?.steps.count, 1)
        XCTAssertEqual(body?.steps.map(\.id.rawValue), ["park"])

        guard let descriptor else { return }
        guard let body = descriptor.body else {
            return XCTFail("Vehicle do.park recipe descriptor must carry a body")
        }
        let parseErrors = FleetRecipeBodyParser.validate(
            body,
            against: descriptor,
            recipes: FleetRecipesCatalogue.shared,
            commands: FleetCommandsCatalogue.shared
        )
        XCTAssertTrue(
            parseErrors.isEmpty,
            "Vehicle do.park recipe body must validate (bundle JSON or compiled-in): \(parseErrors)"
        )
    }

    func test_registerAll_registersDoContinueMissionAfterOperatorPark() {
        FleetMissionRecipeRegistrations.registerAll()

        let name = FleetMissionRecipeRegistrations.doContinueMissionAfterOperatorParkRecipeName
        let descriptor = FleetRecipesCatalogue.shared.descriptor(for: name)
        XCTAssertNotNil(descriptor)
        XCTAssertEqual(descriptor?.riskTier, .confirmInLiveMission)
        XCTAssertEqual(descriptor?.appliesToSystems, ["mission"])
        XCTAssertTrue(descriptor?.parameters.isEmpty ?? false)

        let body = descriptor?.body
        XCTAssertEqual(body?.entryStepID.rawValue, "stopOffboard")
        XCTAssertEqual(body?.steps.count, 4)
        XCTAssertEqual(body?.steps.map(\.id.rawValue), ["stopOffboard", "modeMission", "arm", "startMission"])

        guard let descriptor else { return }
        guard let body = descriptor.body else {
            return XCTFail("Continue-after-park recipe descriptor must carry a body")
        }
        let parseErrors = FleetRecipeBodyParser.validate(
            body,
            against: descriptor,
            recipes: FleetRecipesCatalogue.shared,
            commands: FleetCommandsCatalogue.shared
        )
        XCTAssertTrue(
            parseErrors.isEmpty,
            "Continue-after-park recipe body must validate: \(parseErrors)"
        )
    }
}
