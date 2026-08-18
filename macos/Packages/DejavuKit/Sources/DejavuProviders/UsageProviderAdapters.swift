import Foundation
import DejavuApplication
import DejavuDomain

extension ClaudeStatusSnapshotProvider: UsageProviding {
    public func fetchUsage() async throws -> ClaudeUsageSnapshot {
        do {
            return try await fetchUsage(now: Date())
        } catch let error as ClaudeStatusSnapshotProviderError {
            switch error {
            case .snapshotUnavailable:
                throw UsageProviderFailure.loginRequired
            case .snapshotStale, .snapshotTooLarge, .invalidSnapshot:
                throw UsageProviderFailure.unavailable
            }
        } catch {
            throw UsageProviderFailure.failed
        }
    }
}
