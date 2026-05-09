public struct ConnectionLogEntry: Equatable, Sendable {
    public let message: String

    public init(message: String) {
        self.message = message
    }
}

public struct RingConnectionLog: Equatable, Sendable {
    public private(set) var entries: [ConnectionLogEntry]
    public let capacity: Int

    public init(capacity: Int) {
        self.capacity = max(0, capacity)
        self.entries = []
    }

    public mutating func append(_ entry: ConnectionLogEntry) {
        guard capacity > 0 else { return }
        entries.append(entry)
        if entries.count > capacity {
            entries.removeFirst(entries.count - capacity)
        }
    }
}
