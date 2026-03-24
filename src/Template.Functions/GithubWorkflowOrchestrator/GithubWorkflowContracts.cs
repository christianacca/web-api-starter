using System.ComponentModel.DataAnnotations;
using Template.Shared.Azure.MessageQueue;

namespace Template.Functions.GithubWorkflowOrchestrator;

public static class GithubWorkflowMessageTypes {
  public const string GithubWorkflowInProgress = "GithubWorkflowInProgress";
  public const string GithubWorkflowCompleted = "GithubWorkflowCompleted";

  public static bool IsSupported(string? messageType) {
    return string.Equals(messageType, GithubWorkflowInProgress, StringComparison.Ordinal) ||
           string.Equals(messageType, GithubWorkflowCompleted, StringComparison.Ordinal);
  }
}

public static class GithubWorkflowQueueMessageContract {
  public static void Check(MessageBody messageBody) {
    ArgumentNullException.ThrowIfNull(messageBody);

    var messageType = GetMessageType(messageBody);

    if (messageBody.Metadata == null) {
      throw new ValidationException($"Workflow queue message metadata is missing for message type '{messageType}'.");
    }

    if (!GithubWorkflowMessageTypes.IsSupported(messageType)) {
      throw new ValidationException($"Unsupported workflow queue message type '{messageType}'.");
    }

    if (string.IsNullOrWhiteSpace(messageBody.Data)) {
      throw new ValidationException($"Workflow queue message data is missing for message type '{messageType}'.");
    }

    switch (messageType) {
      case GithubWorkflowMessageTypes.GithubWorkflowInProgress:
        DeserializeAndValidate<GithubWorkflowInProgressMessageData>(messageBody.Data, messageType);
        break;
      case GithubWorkflowMessageTypes.GithubWorkflowCompleted:
        DeserializeAndValidate<GithubWorkflowCompletedMessageData>(messageBody.Data, messageType);
        break;
    }
  }

  private static string GetMessageType(MessageBody messageBody) {
    return messageBody.Metadata?.MessageType ?? "<missing>";
  }

  private static T DeserializeAndValidate<T>(string json, string messageType) where T : class {
    var model = System.Text.Json.JsonSerializer.Deserialize<T>(json);
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