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

    public var routingRuleManifest: RuntimeRoutingRuleManifest {
        snapshot.routingRuleManifest
    }

    public init(snapshot: RuntimeSnapshot, routingEngine: RoutingEngine, batchLimit: Int, flowLimit: Int) {
        self.snapshot = snapshot
        self.routingEngine = routingEngine
        self.batchLimit = max(0, batchLimit)
        self.flowLimit = max(0, flowLimit)
    }

    public init(snapshot: RuntimeSnapshot, batchLimit: Int, flowLimit: Int) throws {
        let rules = try RuntimeRoutingRuleAdapter.routingRules(from: snapshot.routingRuleManifest)
        self.init(
            snapshot: snapshot,
            routingEngine: RoutingEngine(rules: rules),
            batchLimit: batchLimit,
            flowLimit: flowLimit
        )
    }
}
