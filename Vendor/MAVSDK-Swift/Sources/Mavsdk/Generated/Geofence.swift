import Foundation
import GRPC
import NIO
import RxSwift

/**
 Enable setting a geofence.
 */
public class Geofence {
    private let service: Mavsdk_Rpc_Geofence_GeofenceServiceClient
    private let scheduler: SchedulerType
    private let clientEventLoopGroup: EventLoopGroup

    public convenience init(
        address: String = "localhost",
        port: Int32 = 50051,
        scheduler: SchedulerType = ConcurrentDispatchQueueScheduler(qos: .background)
    ) {
        let eventLoopGroup = MultiThreadedEventLoopGroup(numberOfThreads: 2)
        let channel = ClientConnection.insecure(group: eventLoopGroup).connect(host: address, port: Int(port))
        let service = Mavsdk_Rpc_Geofence_GeofenceServiceClient(channel: channel)

        self.init(service: service, scheduler: scheduler, eventLoopGroup: eventLoopGroup)
    }

    init(service: Mavsdk_Rpc_Geofence_GeofenceServiceClient, scheduler: SchedulerType, eventLoopGroup: EventLoopGroup) {
        self.service = service
        self.scheduler = scheduler
        self.clientEventLoopGroup = eventLoopGroup
    }

    public struct RuntimeGeofenceError: Error {
        public let description: String

        init(_ description: String) {
            self.description = description
        }
    }

    public struct GeofenceError: Error {
        public let code: Geofence.GeofenceResult.Result
        public let description: String
    }

    /// Inclusion / exclusion semantics shared by polygons and circles (``mavsdk.rpc.geofence.FenceType``).
    public enum FenceType: Equatable {
        case inclusion
        case exclusion
        case UNRECOGNIZED(Int)

        internal var rpcFenceType: Mavsdk_Rpc_Geofence_FenceType {
            switch self {
            case .inclusion: return .inclusion
            case .exclusion: return .exclusion
            case .UNRECOGNIZED(let i): return .UNRECOGNIZED(i)
            }
        }

        internal static func translateFromRpc(_ rpcFenceType: Mavsdk_Rpc_Geofence_FenceType) -> FenceType {
            switch rpcFenceType {
            case .inclusion: return .inclusion
            case .exclusion: return .exclusion
            case .UNRECOGNIZED(let i): return .UNRECOGNIZED(i)
            }
        }
    }

    /**
     Point type.
     */
    public struct Point: Equatable {
        public let latitudeDeg: Double
        public let longitudeDeg: Double

        public init(latitudeDeg: Double, longitudeDeg: Double) {
            self.latitudeDeg = latitudeDeg
            self.longitudeDeg = longitudeDeg
        }

        internal var rpcPoint: Mavsdk_Rpc_Geofence_Point {
            var rpcPoint = Mavsdk_Rpc_Geofence_Point()
            rpcPoint.latitudeDeg = latitudeDeg
            rpcPoint.longitudeDeg = longitudeDeg
            return rpcPoint
        }

        internal static func translateFromRpc(_ rpcPoint: Mavsdk_Rpc_Geofence_Point) -> Point {
            Point(latitudeDeg: rpcPoint.latitudeDeg, longitudeDeg: rpcPoint.longitudeDeg)
        }

        public static func == (lhs: Point, rhs: Point) -> Bool {
            lhs.latitudeDeg == rhs.latitudeDeg && lhs.longitudeDeg == rhs.longitudeDeg
        }
    }

    /**
     Polygon type.
     */
    public struct Polygon: Equatable {
        public let points: [Point]
        public let fenceType: FenceType

        public init(points: [Point], fenceType: FenceType) {
            self.points = points
            self.fenceType = fenceType
        }

        internal var rpcPolygon: Mavsdk_Rpc_Geofence_Polygon {
            var rpcPolygon = Mavsdk_Rpc_Geofence_Polygon()
            rpcPolygon.points = points.map(\.rpcPoint)
            rpcPolygon.fenceType = fenceType.rpcFenceType
            return rpcPolygon
        }

        internal static func translateFromRpc(_ rpcPolygon: Mavsdk_Rpc_Geofence_Polygon) -> Polygon {
            Polygon(
                points: rpcPolygon.points.map { Point.translateFromRpc($0) },
                fenceType: FenceType.translateFromRpc(rpcPolygon.fenceType)
            )
        }

        public static func == (lhs: Polygon, rhs: Polygon) -> Bool {
            lhs.points == rhs.points && lhs.fenceType == rhs.fenceType
        }
    }

    /**
     Circular geofence (center point + radius in metres).
     */
    public struct Circle: Equatable {
        public let point: Point
        public let radius: Float
        public let fenceType: FenceType

        public init(point: Point, radius: Float, fenceType: FenceType) {
            self.point = point
            self.radius = radius
            self.fenceType = fenceType
        }

        internal var rpcCircle: Mavsdk_Rpc_Geofence_Circle {
            var c = Mavsdk_Rpc_Geofence_Circle()
            c.point = point.rpcPoint
            c.radius = radius
            c.fenceType = fenceType.rpcFenceType
            return c
        }

        internal static func translateFromRpc(_ rpcCircle: Mavsdk_Rpc_Geofence_Circle) -> Circle {
            Circle(
                point: Point.translateFromRpc(rpcCircle.point),
                radius: rpcCircle.radius,
                fenceType: FenceType.translateFromRpc(rpcCircle.fenceType)
            )
        }

        public static func == (lhs: Circle, rhs: Circle) -> Bool {
            lhs.point == rhs.point && lhs.radius == rhs.radius && lhs.fenceType == rhs.fenceType
        }
    }

    /**
     Combined geofence upload payload (polygons and/or circles).
     */
    public struct GeofenceData: Equatable {
        public let polygons: [Polygon]
        public let circles: [Circle]

        public init(polygons: [Polygon], circles: [Circle]) {
            self.polygons = polygons
            self.circles = circles
        }

        internal var rpcGeofenceData: Mavsdk_Rpc_Geofence_GeofenceData {
            var d = Mavsdk_Rpc_Geofence_GeofenceData()
            d.polygons = polygons.map(\.rpcPolygon)
            d.circles = circles.map(\.rpcCircle)
            return d
        }

        public static func == (lhs: GeofenceData, rhs: GeofenceData) -> Bool {
            lhs.polygons == rhs.polygons && lhs.circles == rhs.circles
        }
    }

    /**
     Result type.
     */
    public struct GeofenceResult: Equatable {
        public let result: Result
        public let resultStr: String

        public enum Result: Equatable {
            case unknown
            case success
            case error
            case tooManyGeofenceItems
            case busy
            case timeout
            case invalidArgument
            case noSystem
            case UNRECOGNIZED(Int)

            internal var rpcResult: Mavsdk_Rpc_Geofence_GeofenceResult.Result {
                switch self {
                case .unknown: return .unknown
                case .success: return .success
                case .error: return .error
                case .tooManyGeofenceItems: return .tooManyGeofenceItems
                case .busy: return .busy
                case .timeout: return .timeout
                case .invalidArgument: return .invalidArgument
                case .noSystem: return .noSystem
                case .UNRECOGNIZED(let i): return .UNRECOGNIZED(i)
                }
            }

            internal static func translateFromRpc(_ rpcResult: Mavsdk_Rpc_Geofence_GeofenceResult.Result) -> Result {
                switch rpcResult {
                case .unknown: return .unknown
                case .success: return .success
                case .error: return .error
                case .tooManyGeofenceItems: return .tooManyGeofenceItems
                case .busy: return .busy
                case .timeout: return .timeout
                case .invalidArgument: return .invalidArgument
                case .noSystem: return .noSystem
                case .UNRECOGNIZED(let i): return .UNRECOGNIZED(i)
                }
            }
        }

        public init(result: Result, resultStr: String) {
            self.result = result
            self.resultStr = resultStr
        }

        internal var rpcGeofenceResult: Mavsdk_Rpc_Geofence_GeofenceResult {
            var rpcGeofenceResult = Mavsdk_Rpc_Geofence_GeofenceResult()
            rpcGeofenceResult.result = result.rpcResult
            rpcGeofenceResult.resultStr = resultStr
            return rpcGeofenceResult
        }

        internal static func translateFromRpc(_ rpcGeofenceResult: Mavsdk_Rpc_Geofence_GeofenceResult) -> GeofenceResult {
            GeofenceResult(result: Result.translateFromRpc(rpcGeofenceResult.result), resultStr: rpcGeofenceResult.resultStr)
        }

        public static func == (lhs: GeofenceResult, rhs: GeofenceResult) -> Bool {
            lhs.result == rhs.result && lhs.resultStr == rhs.resultStr
        }
    }

    /**
     Upload a geofence plan (polygons and/or circles). Persists on the vehicle after upload.
     */
    public func uploadGeofence(geofenceData: GeofenceData) -> Completable {
        Completable.create { completable in
            var request = Mavsdk_Rpc_Geofence_UploadGeofenceRequest()
            request.geofenceData = geofenceData.rpcGeofenceData

            do {
                let response = self.service.uploadGeofence(request)
                let result = try response.response.wait().geofenceResult
                if result.result == Mavsdk_Rpc_Geofence_GeofenceResult.Result.success {
                    completable(.completed)
                } else {
                    completable(.error(GeofenceError(
                        code: GeofenceResult.Result.translateFromRpc(result.result),
                        description: result.resultStr
                    )))
                }
            } catch {
                completable(.error(error))
            }

            return Disposables.create()
        }
    }

    /**
     Convenience: upload polygons and optional circles as one ``GeofenceData`` request.
     */
    public func uploadGeofence(polygons: [Polygon], circles: [Circle] = []) -> Completable {
        uploadGeofence(geofenceData: GeofenceData(polygons: polygons, circles: circles))
    }

    /**
     Clear all geofences saved on the vehicle.
     */
    public func clearGeofence() -> Completable {
        Completable.create { completable in
            let request = Mavsdk_Rpc_Geofence_ClearGeofenceRequest()

            do {
                let response = self.service.clearGeofence(request)
                let result = try response.response.wait().geofenceResult
                if result.result == Mavsdk_Rpc_Geofence_GeofenceResult.Result.success {
                    completable(.completed)
                } else {
                    completable(.error(GeofenceError(
                        code: GeofenceResult.Result.translateFromRpc(result.result),
                        description: result.resultStr
                    )))
                }
            } catch {
                completable(.error(error))
            }

            return Disposables.create()
        }
    }
}
