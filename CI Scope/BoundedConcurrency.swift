import Foundation

/// Runs `transform` over `items` with at most `maxConcurrent` tasks in flight
/// instead of an unbounded fan-out. GitHub's secondary ("abuse") rate limit is
/// triggered by bursts of simultaneous requests, so capping concurrency keeps
/// the monitor under that threshold. Result order is not preserved.
func mapConcurrently<Item: Sendable, Output: Sendable>(
    _ items: [Item],
    maxConcurrent: Int,
    _ transform: @Sendable @escaping (Item) async -> Output
) async -> [Output] {
    guard !items.isEmpty else { return [] }
    let limit = max(1, min(maxConcurrent, items.count))

    return await withTaskGroup(of: Output.self) { group in
        var output: [Output] = []
        output.reserveCapacity(items.count)
        var next = 0

        while next < limit {
            let item = items[next]
            group.addTask { await transform(item) }
            next += 1
        }

        while let result = await group.next() {
            output.append(result)
            guard next < items.count else { continue }
            let item = items[next]
            group.addTask { await transform(item) }
            next += 1
        }

        return output
    }
}
