namespace Template.Shared.Github;

public static class WorkflowRunHelper {
  public static string? ExtractInstanceId(string workflowRunName, string workflowNamePrefix) {
    return !workflowRunName.StartsWith(workflowNamePrefix, StringComparison.OrdinalIgnoreCase)
      ? null
      : workflowRunName[workflowNamePrefix.Length..];
  }
}
