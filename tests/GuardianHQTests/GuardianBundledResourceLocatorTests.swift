import XCTest
@testable import GuardianCore

final class GuardianBundledResourceLocatorTests: XCTestCase {
    func test_trainingSimulationBundles_resolveGazeboWebViewer() {
        let url = GuardianBundledResourceLocator.gazeboWebViewerHTMLURL()
        XCTAssertNotNil(url, "Expected guardian_viewer.html in the Training simulation resource bundle")
    }

    func test_trainingSimulationBundles_resolveTrainingEnvironments() {
        let root = GuardianBundledResourceLocator.subdirectoryURL(
            "TrainingEnvironments",
            in: GuardianBundledResourceLocator.trainingSimulationResourceBundles
        )
        XCTAssertNotNil(root)
    }
}
