namespace Template.Shared.Github;

/// <summary>
/// The name of the function app that dispatches and receives GitHub workflow callbacks.
/// </summary>
/// <remarks>
/// This name is used as the prefix for workflow run names (e.g. <c>InternalApi-&lt;instanceId&gt;</c>)
/// and must match the corresponding sub-product key in the product conventions so that the
/// queue-callback workflow can resolve the correct storage account when publishing events.
/// </remarks>
public sealed record FunctionAppName(string Value);
