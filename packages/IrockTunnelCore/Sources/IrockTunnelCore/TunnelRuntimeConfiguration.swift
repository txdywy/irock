import IrockCore
import IrockRouting

public struct TunnelRuntimeConfiguration: Sendable {
    public let snapshot: RuntimeSnapshot
    public let routingEngine: RoutingEngine
    public let batchLimit: Int
    public let flowLimit: Int

    public var routeMode: RouteMode {
        snapshot.routeMode
    }

    public init(snapshot: RuntimeSnapshot, routingEngine: RoutingEngine, batchLimit: Int, flowLimit: Int) {
        self.snapshot = snapshot
        self.routingEngine = routingEngine
        self.batchLimit = max(0, batchLimit)
        self.flowLimit = max(0, flowLimit)
    }
}
