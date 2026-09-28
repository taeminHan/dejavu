import Foundation
import DejavuApplication
import DejavuDomain

extension ClaudeStatusSnapshotProvider: UsageProviding {
    public func fetchUsage() async throws -> ClaudeUsageSnapshot {
        do {
            return try await fetchUsage(now: now())
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

extension ClaudeDesktopHistoryProvider: UsageProviding {
    public func fetchUsage() async throws -> ClaudeUsageSnapshot {
        do {
            return try await fetchUsage(now: now())
        } catch let error as ClaudeDesktopHistoryProviderError {
            // A sample past the freshness window but within a week already
            // arrives as a snapshot without values. Missing, unreadable or
            // week-old history means Desktop is not in use; it is never a
            // sign-in problem.
            switch error {
            case .historyUnavailable, .historyStale, .historyTooLarge, .invalidHistory:
                throw UsageProviderFailure.unavailable
            }
        } catch {
            throw UsageProviderFailure.failed
        }
    }
}
