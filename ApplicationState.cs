namespace ClaudeUsageTray;

internal enum UsageStatus
{
    Loading,
    Ready,
    LoginRequired,
    RateLimited,
    Offline,
    Error
}

internal sealed record ApplicationState(
    UsageStatus Status,
    UsageSnapshot? Snapshot,
    string Message,
    DateTimeOffset? UpdatedAt,
    DateTimeOffset? RetryAt = null,
    CodexUsageSnapshot? CodexSnapshot = null,
    UsageStatus ClaudeStatus = UsageStatus.Loading,
    UsageStatus CodexStatus = UsageStatus.Loading,
    string ClaudeMessage = "Claude 확인 중",
    string CodexMessage = "Codex 확인 중")
{
    public static ApplicationState Loading(UsageSnapshot? previous = null, CodexUsageSnapshot? previousCodex = null) =>
        new(UsageStatus.Loading, previous, previous is null && previousCodex is null
                ? "사용량을 확인하고 있어요" : "새 사용량을 확인하고 있어요", null,
            CodexSnapshot: previousCodex, ClaudeStatus: UsageStatus.Loading, CodexStatus: UsageStatus.Loading);
}
