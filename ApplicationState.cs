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
    // The overall Loading status marks a refresh in flight. Each provider keeps its last settled
    // status, message and UpdatedAt, so a provider status of Loading means "never checked yet"
    // and a periodic refresh never looks like a lost connection.
    public static ApplicationState Loading(ApplicationState? previous = null) =>
        previous is null
            ? new(UsageStatus.Loading, null, "사용량을 확인하고 있어요", null)
            : previous with
            {
                Status = UsageStatus.Loading,
                Message = previous.Snapshot is null && previous.CodexSnapshot is null
                    ? "사용량을 확인하고 있어요" : "새 사용량을 확인하고 있어요"
            };
}
