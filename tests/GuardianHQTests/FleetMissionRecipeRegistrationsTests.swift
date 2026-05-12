import XCTest
@testable import GuardianHQ

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

        let body = descriptor?.body
        XCTAssertEqual(body?.entryStepID.rawValue, "upload")
        XCTAssertEqual(body?.steps.count, 3)
        XCTAssertEqual(body?.steps.map(\.id.rawValue), ["upload", "arm", "start"])

        guard let descriptor else { return }
        let parseErrors = FleetRecipeBodyParser.validate(
            descriptor.body,
            against: descriptor,
            recipes: FleetRecipesCatalogue.shared,
            commands: FleetCommandsCatalogue.shared
        )
        XCTAssertTrue(
            parseErrors.isEmpty,
            "Mission upload/start recipe body must validate (bundle JSON or compiled-in): \(parseErrors)"
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
        let parseErrors = FleetRecipeBodyParser.validate(
            descriptor.body,
            against: descriptor,
            recipes: FleetRecipesCatalogue.shared,
            commands: FleetCommandsCatalogue.shared
        )
        XCTAssertTrue(
            parseErrors.isEmpty,
            "Return-home recipe body must validate (bundle JSON or compiled-in): \(parseErrors)"
        )
    }
}
