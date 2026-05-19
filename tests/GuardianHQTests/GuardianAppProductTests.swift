import XCTest
@testable import GuardianHQ

final class GuardianAppProductTests: XCTestCase {
    func test_missionProduct_excludesTrainingSection() {
        let product = GuardianAppProduct.mission
        XCTAssertTrue(product.includesSidebarSection(.missions))
        XCTAssertTrue(product.includesSidebarSection(.missionControl))
        XCTAssertFalse(product.includesSidebarSection(.training))
        XCTAssertFalse(product.includesSidebarSection(.worlds))
        XCTAssertTrue(product.includesSidebarSection(.brains))
    }

    func test_trainingProduct_excludesMissionPanels_keepsGarageAndTraining() {
        let product = GuardianAppProduct.training
        XCTAssertFalse(product.includesSidebarSection(.missions))
        XCTAssertFalse(product.includesSidebarSection(.missionControl))
        XCTAssertFalse(product.includesSidebarSection(.liveDrive))
        XCTAssertTrue(product.includesSidebarSection(.devices))
        XCTAssertTrue(product.includesSidebarSection(.training))
        XCTAssertEqual(product.defaultAppSection, .dashboard)
    }

    func test_trainingPrimaryRail_includesTrainingWithoutSimulateToggle() {
        let product = GuardianAppProduct.training
        let rail = product.primarySidebarRail(simulateEnabled: false)
        XCTAssertTrue(rail.contains(.training))
        XCTAssertFalse(rail.contains(.missions))
        XCTAssertFalse(rail.contains(.brains))
    }

    func test_branding_assetsAndSplashCopy() {
        XCTAssertEqual(GuardianAppProduct.mission.displayName, "Guardian Mission")
        XCTAssertEqual(GuardianAppProduct.training.displayName, "Guardian Training")
        XCTAssertEqual(GuardianAppProduct.mission.sidebarLogoResourceName, "sidebar_logo")
        XCTAssertEqual(GuardianAppProduct.training.sidebarLogoResourceName, "sidebar_logo_training")
        XCTAssertEqual(GuardianAppProduct.mission.splashLogoResourceName, "splash_logo_mission")
        XCTAssertEqual(GuardianAppProduct.training.splashLogoResourceName, "splash_logo_training")
        XCTAssertEqual(GuardianAppProduct.mission.dockLogoResourceName, "dock_logo_mission")
        XCTAssertEqual(GuardianAppProduct.training.dockLogoResourceName, "dock_logo_training")
        XCTAssertEqual(GuardianAppProduct.mission.splashHeadline, "GUARDIAN MISSION")
        XCTAssertEqual(GuardianAppProduct.training.splashHeadline, "GUARDIAN TRAINING")
    }
}
