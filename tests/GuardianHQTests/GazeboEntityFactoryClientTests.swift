import XCTest
@testable import GuardianHQ

final class GazeboEntityFactoryClientTests: XCTestCase {
    func test_parseBooleanServiceResponse_blockingTrue() {
        XCTAssertTrue(
            GazeboEntityFactoryClient.parseBooleanServiceResponse(
                "data: true\n",
                policy: .blockingExecuteResult
            )
        )
    }

    func test_parseBooleanServiceResponse_blockingFalse() {
        XCTAssertFalse(
            GazeboEntityFactoryClient.parseBooleanServiceResponse(
                "data: false\n",
                policy: .blockingExecuteResult
            )
        )
    }

    func test_interpretBlockingRemoveResponse_rejectsStderrNotFound() {
        XCTAssertFalse(
            GazeboEntityFactoryClient.interpretBlockingRemoveResponse(
                stdout: "data: true\n",
                stderr: "Entity named [foo] of type [2] not found, so not removed."
            )
        )
    }

    func test_interpretBlockingRemoveResponse_acceptsTrueWithoutError() {
        XCTAssertTrue(
            GazeboEntityFactoryClient.interpretBlockingRemoveResponse(
                stdout: "data: true\n",
                stderr: ""
            )
        )
    }

    func test_interpretBlockingRemoveResponse_acceptsEmptyStdoutWhenNoError() {
        XCTAssertTrue(
            GazeboEntityFactoryClient.interpretBlockingRemoveResponse(
                stdout: "",
                stderr: ""
            )
        )
    }

    func test_parseModelListOutput_extractsNames() {
        let text = """
        Requesting state for world [guardian_open_field]...

        Available models:
            - open_field_floor
            - guardian_obstacle_abc
        """
        XCTAssertEqual(
            GazeboEntityFactoryClient.parseModelListOutput(text),
            ["open_field_floor", "guardian_obstacle_abc"]
        )
    }

    func test_parseBooleanServiceResponse_asyncEmptyIsAck() {
        XCTAssertTrue(
            GazeboEntityFactoryClient.parseBooleanServiceResponse(
                "",
                policy: .asyncQueueAck
            )
        )
    }
}
