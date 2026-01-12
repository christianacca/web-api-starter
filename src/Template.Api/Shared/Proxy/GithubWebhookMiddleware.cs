using Microsoft.Extensions.Options;
using System.Text.Json;
using Template.Shared.Github;

namespace Template.Api.Shared.Proxy;

public class GithubWebhookMiddleware(
  RequestDelegate next,
  IOptionsMonitor<GithubAppOptions> appOptions,
  ILogger<GithubWebhookMiddleware> logger) {
  private const string WebhookPath = "/api/workflow/webhook";
  private const string RequestContentType = "application/json";
  private const string InvalidSignatureMessage = "Invalid signature";

  public async Task InvokeAsync(HttpContext context) {
    var request = context.Request;

    if (!IsWebhookRoute(request)) {
      await next(context);
      return;
    }

    request.EnableBuffering();

    var body = await ReadRequestBodyAsync(request);

    if (!await ValidateSignatureOrRejectAsync(request, body, context)) {
      return;
    }

    ExtractAndSetCorrelationId(request, body);

    await next(context);
  }

  private static async Task<string> ReadRequestBodyAsync(HttpRequest request) {
    using var reader = new StreamReader(request.Body, leaveOpen: true);
    var body = await reader.ReadToEndAsync();
    request.Body.Position = 0; // Reset position for downstream processing
    return body;
  }

  private async Task<bool> ValidateSignatureOrRejectAsync(HttpRequest request, string body, HttpContext context) {
    request.Headers.TryGetValue(GithubHeaderNames.Signature256, out var signatureHeader);
    var secret = appOptions.CurrentValue.WebhookSecret;

    var isSignatureValid = GithubWebhookSignatureValidator.IsValidSignature(body, signatureHeader, secret);

    if (!isSignatureValid) {
      logger.LogWarning(
        "GitHub webhook signature validation failed for {Path}. Signature: {Signature}",
        request.Path,
        signatureHeader);

      context.Response.StatusCode = StatusCodes.Status401Unauthorized;
      await context.Response.WriteAsync(InvalidSignatureMessage);
    }

    return isSignatureValid;
  }

  private void ExtractAndSetCorrelationId(HttpRequest request, string body) {
    using var jsonDocument = JsonDocument.Parse(body);
    var correlationId = TryGetWorkflowRunName(jsonDocument);

    if (!request.Headers.ContainsKey(GithubHeaderNames.WorkflowCorrelationId) && !string.IsNullOrEmpty(correlationId)) {
      request.Headers.TryAdd(GithubHeaderNames.WorkflowCorrelationId, correlationId);
    }
  }

  private static string? TryGetWorkflowRunName(JsonDocument jsonDocument) {
    if (jsonDocument.RootElement.TryGetProperty("workflow_run", out var workflowRun) &&
        workflowRun.TryGetProperty("name", out var runName)) {
      return runName.GetString();
    }

    return null;
  }

  private static bool IsWebhookRoute(HttpRequest request) =>
    request.Path.StartsWithSegments(WebhookPath)
    && request.Method == HttpMethods.Post
    && request.ContentType?.Contains(RequestContentType) == true;
}
