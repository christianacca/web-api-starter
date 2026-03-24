using System.ComponentModel.DataAnnotations;
using System.Text.Json;
using Template.Shared.Azure.MessageQueue;
using Template.Shared.Extensions;

namespace Template.Functions.GithubWorkflowOrchestrator;

public static class GithubWorkflowMessageTypes {
  public const string GithubWorkflowInProgress = "GithubWorkflowInProgress";
  public const string GithubWorkflowCompleted = "GithubWorkflowCompleted";
}

public static class GithubWorkflowQueueMessageContract {
  private static readonly JsonSerializerOptions PayloadSerializerOptions = CreatePayloadSerializerOptions();

  private static readonly IReadOnlyDictionary<string, Action<string>> ValidatorsByMessageType =
    new Dictionary<string, Action<string>>(StringComparer.Ordinal) {
      [GithubWorkflowMessageTypes.GithubWorkflowInProgress] = json => DeserializeAndValidate<GithubWorkflowInProgressMessageData>(json, GithubWorkflowMessageTypes.GithubWorkflowInProgress),
      [GithubWorkflowMessageTypes.GithubWorkflowCompleted] = json => DeserializeAndValidate<GithubWorkflowCompletedMessageData>(json, GithubWorkflowMessageTypes.GithubWorkflowCompleted)
    };

  public static void Check(MessageBody messageBody) {
    ArgumentNullException.ThrowIfNull(messageBody);

    var messageType = messageBody.Metadata?.MessageType ?? throw new ValidationException("Workflow queue message metadata is missing.");

    if (string.IsNullOrWhiteSpace(messageBody.Data)) {
      throw new ValidationException($"Workflow queue message data is missing for message type '{messageType}'.");
    }

    if (!ValidatorsByMessageType.TryGetValue(messageType, out var validatePayload)) {
      throw new ValidationException($"Unsupported workflow queue message type '{messageType}'.");
    }

    validatePayload(messageBody.Data);
  }

  public static bool IsSupported(string? messageType) {
    return !string.IsNullOrWhiteSpace(messageType) && ValidatorsByMessageType.ContainsKey(messageType);
  }

  private static T DeserializeAndValidate<T>(string json, string messageType) where T : class {
    var model = JsonSerializer.Deserialize<T>(json, PayloadSerializerOptions);
    if (model == null) {
      throw new ValidationException($"Workflow queue message data is missing for message type '{messageType}'.");
    }

    try {
      Validator.ValidateObject(model, new ValidationContext(model), validateAllProperties: true);
    }
    catch (ValidationException ex) {
      throw new ValidationException(
        $"Workflow queue message validation failed for message type '{messageType}': {ex.Message}",
        ex.ValidationAttribute,
        ex.Value);
    }

    return model;
  }

  private static JsonSerializerOptions CreatePayloadSerializerOptions() {
    var options = new JsonSerializerOptions();
    options.ConfigureStandardOptions();
    return options;
  }
}

public abstract class GithubWorkflowQueueMessageBase {
  [Required(AllowEmptyStrings = false)]
  public string Environment { get; set; } = null!;

  [Required(AllowEmptyStrings = false)]
  public string InstanceId { get; set; } = null!;

  [Required(AllowEmptyStrings = false)]
  [RegularExpression(@"^[^/]+/[^/]+$", ErrorMessage = "Repository must be in 'owner/repo' format.")]
  public string Repository { get; set; } = null!;

  [Range(1, long.MaxValue)]
  public long RunId { get; set; }

  [Range(1, int.MaxValue)]
  public int RunAttempt { get; set; }

  [Required(AllowEmptyStrings = false)]
  public string WorkflowName { get; set; } = null!;
}

public sealed class GithubWorkflowInProgressMessageData : GithubWorkflowQueueMessageBase;

public sealed class GithubWorkflowCompletedMessageData : GithubWorkflowQueueMessageBase {
  [Required(AllowEmptyStrings = false)]
  public string Conclusion { get; set; } = null!;
}