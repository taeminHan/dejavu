using System.Reflection;
using System.Text.Json;

// Synthetic responses only. Calls the production parser without starting the app,
// reading credentials/history/settings, running a provider or making HTTP requests.
var assembly = Assembly.Load("dejavu");
var clientType = assembly.GetType("ClaudeUsageTray.ClaudeUsageClient", throwOnError: true)!;
var parse = clientType.GetMethod("ParseUsage", BindingFlags.Static | BindingFlags.NonPublic)
    ?? throw new MissingMethodException("ClaudeUsageClient.ParseUsage");
var reset = DateTimeOffset.Parse("2027-01-04T12:00:00Z");
var cases = new ParserCase[]
{
    new("missing-all", "{}", null),
    new("legacy-opus-only", """{"seven_day_opus":{"utilization":37}}""", null),
    new("legacy-sonnet-only", """{"seven_day_sonnet":{"utilization":62}}""", null),
    new("legacy-opus-and-sonnet", """{"seven_day_opus":{"utilization":37},"seven_day_sonnet":{"utilization":62}}""", null),
    new("legacy-fable", """{"seven_day_fable":{"utilization":19,"resets_at":"2027-01-04T12:00:00Z"}}""", 19, FableReset: reset),
    new("legacy-fable-zero", """{"seven_day_fable":{"utilization":0},"seven_day_opus":{"utilization":37}}""", 0),
    new("legacy-fable-wins", """{"seven_day_fable":{"utilization":19},"seven_day_opus":{"utilization":37},"seven_day_sonnet":{"utilization":62}}""", 19),
    new("legacy-fable-null", """{"seven_day_fable":null,"seven_day_opus":{"utilization":37}}""", null),
    new("legacy-fable-missing-percent", """{"seven_day_fable":{},"seven_day_sonnet":{"utilization":62}}""", null),
    new("legacy-fable-invalid-percent", """{"seven_day_fable":{"utilization":null},"seven_day_opus":{"utilization":37}}""", null, ExpectSchemaError: true),
    new("modern-opus-only", """{"limits":[{"kind":"weekly_scoped","scope":{"model":{"display_name":"Opus"}},"percent":37}]}""", null),
    new("modern-sonnet-only", """{"limits":[{"kind":"weekly_scoped","scope":{"model":{"display_name":"Sonnet"}},"percent":62}]}""", null),
    new("modern-fable", """{"limits":[{"kind":"weekly_scoped","scope":{"model":{"display_name":"Fable"}},"percent":19,"resets_at":"2027-01-04T12:00:00Z"}]}""", 19, FableReset: reset),
    new("modern-fable-zero", """{"limits":[{"kind":"weekly_scoped","scope":{"model":{"display_name":"Fable"}},"percent":0}]}""", 0),
    new("modern-fable-case-insensitive", """{"limits":[{"kind":"weekly_scoped","scope":{"model":{"display_name":"fable"}},"percent":19}]}""", 19),
    new("modern-fable-wins-over-legacy", """{"limits":[{"kind":"weekly_scoped","scope":{"model":{"display_name":"Opus"}},"percent":37},{"kind":"weekly_scoped","scope":{"model":{"display_name":"Fable"}},"percent":19}],"seven_day_fable":{"utilization":81},"seven_day_sonnet":{"utilization":62}}""", 19),
    new("modern-fable-absent-legacy-opus", """{"limits":[],"seven_day_opus":{"utilization":37}}""", null),
    new("modern-fable-absent-legacy-fable", """{"limits":[],"seven_day_fable":{"utilization":19}}""", 19),
    new("legacy-other-windows-preserved", """{"five_hour":{"utilization":12},"seven_day":{"utilization":45},"seven_day_opus":{"utilization":37}}""", null, 12, 45),
    new("modern-other-windows-preserved", """{"limits":[{"kind":"session","percent":12},{"kind":"weekly_all","percent":45},{"kind":"weekly_scoped","scope":{"model":{"display_name":"Fable"}},"percent":19}]}""", 19, 12, 45)
};
var failures = new List<string>();
foreach (var item in cases)
{
    using var document = JsonDocument.Parse(item.Json);
    object snapshot;
    try
    {
        snapshot = parse.Invoke(null, [document.RootElement])!;
    }
    catch (TargetInvocationException exception) when (item.ExpectSchemaError &&
                                                     exception.InnerException is InvalidOperationException)
    {
        // Preserve malformed-response handling; this fix only removes model substitution.
        continue;
    }
    if (item.ExpectSchemaError)
    {
        failures.Add(item.Name + ": malformed response was silently accepted");
        continue;
    }
    foreach (var metric in new[]
    {
        (Name: "Fable", Expected: item.Fable),
        (Name: "FiveHour", Expected: item.FiveHour),
        (Name: "Weekly", Expected: item.Weekly)
    })
    {
        var limit = snapshot.GetType().GetProperty(metric.Name)!.GetValue(snapshot);
        var percent = limit is null ? (double?)null
            : (double)limit.GetType().GetProperty("Percent")!.GetValue(limit)!;
        if (percent != metric.Expected) failures.Add(item.Name + ": wrong " + metric.Name);
        if (metric.Name == "Fable" && limit is not null)
        {
            var resetsAt = (DateTimeOffset?)limit.GetType().GetProperty("ResetsAt")!.GetValue(limit);
            if (resetsAt != item.FableReset) failures.Add(item.Name + ": wrong Fable reset time");
        }
    }
}
Console.WriteLine($"Claude usage parser: {cases.Length} checked, {failures.Count} failures");
foreach (var failure in failures) Console.Error.WriteLine("CLAUDE PARSER " + failure);
return failures.Count == 0 ? 0 : 1;

internal sealed record ParserCase(string Name, string Json, double? Fable,
    double? FiveHour = null, double? Weekly = null, DateTimeOffset? FableReset = null,
    bool ExpectSchemaError = false);
