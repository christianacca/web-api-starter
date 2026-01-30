using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Extensions.Options;
using System.Text.Json;
using Template.Shared.Github;

namespace Template.Api.Endpoints.GithubWebhookProxy;

[Route("api/workflow")]
[ApiController]
public class GithubWebhookProxyController(
  GithubWebhookProxyService proxyService,
  IOptionsMonitor<GithubAppOptions> appOptions,
  ILogger<GithubWebhookProxyController> logger) : ControllerBase {

  private const string InvalidSignatureMessage = "Invalid signature";

  [AllowAnonymous]
  [HttpPost("webhook")]
  public async Task<IActionResult> Webhook(CancellationToken ct) {
    Request.EnableBuffering();
    using var reader = new StreamReader(Request.Body, leaveOpen: true);
    var body = await reader.ReadToEndAsync(ct);
    Request.Body.Position = 0;

    Request.Headers.TryGetValue(GithubHeaderNames.Signature256, out var signatureHeader);
    var secret = appOptions.CurrentValue.WebhookSecret;
    var isSignatureValid = GithubWebhookSignatureValidator.IsValidSignature(body, signatureHeader, secret);

    if (!isSignatureValid) {
      logger.LogWarning("GitHub webhook signature validation failed for {Path}. Signature: {Signature}",
        Request.Path, signatureHeader);
      return Unauthorized(InvalidSignatureMessage);
    }

    var appIdentifier = TryGetAppIdentifier(body);
    if (!Request.Headers.ContainsKey(GithubHeaderNames.AppIdentifier) && !string.IsNullOrEmpty(appIdentifier)) {
      Request.Headers.Append(GithubHeaderNames.AppIdentifier, appIdentifier);
    }

    if (string.IsNullOrEmpty(appIdentifier)) return BadRequest();
    var response = await proxyService.ForwardWebhookAsync(Request, body, appIdentifier, ct);

    return StatusCode((int)response.StatusCode, await response.Content.ReadAsStringAsync(ct));
  }

  private static string? TryGetAppIdentifier(string body) {
    using var jsonDocument = JsonDocument.Parse(body);
    if (jsonDocument.RootElement.TryGetProperty("workflow_run", out var workflowRun) &&
        workflowRun.TryGetProperty("name", out var runName)) {
      var workflowName = runName.GetString();
      if (!string.IsNullOrEmpty(workflowName)) {
        var parts = workflowName.Split('-', 2);
        if (parts.Length > 1 && !string.IsNullOrEmpty(parts[0])) {
          return parts[0];
        }
      }
    }
    return null;
  }
}
