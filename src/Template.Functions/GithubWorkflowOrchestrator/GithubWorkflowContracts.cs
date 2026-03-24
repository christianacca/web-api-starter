using System.ComponentModel.DataAnnotations;
using Template.Shared.Azure.MessageQueue;

namespace Template.Functions.GithubWorkflowOrchestrator;

public static class GithubWorkflowOrchestrationEvents {
  public const string WorkflowCompleted = "WorkflowCompleted";
  public const string WorkflowInProgress = "WorkflowInProgress";
}

public static class GithubWorkflowQueueMessageTypes {
  public const string GithubWorkflowInProgress = "GithubWorkflowInProgress";
  public const string GithubWorkflowCompleted = "GithubWorkflowCompleted";

  public static bool IsSupported(string? messageType) {
    return string.Equals(messageType, GithubWorkflowInProgress, StringComparison.Ordinal) ||
           string.Equals(messageType, GithubWorkflowCompleted, StringComparison.Ordinal);
  }
}

public static class GithubWorkflowQueueStatuses {
  public const string Completed = "completed";
  public const string InProgress = "in_progress";
}

public static class GithubWorkflowQueueMessageContract {
  public static void Validate(MessageBody messageBody) {
    ArgumentNullException.ThrowIfNull(messageBody);

    if (messageBody.Metadata == null) {
      throw new ValidationException("Message metadata is missing.");
    }

    if (!GithubWorkflowQueueMessageTypes.IsSupported(messageBody.Metadata.MessageType)) {
      throw new ValidationException($"Unsupported workflow queue message type '{messageBody.Metadata.MessageType}'.");
    }

    if (string.IsNullOrWhiteSpace(messageBody.Data)) {
      throw new ValidationException("Message data is missing.");
    }

    switch (messageBody.Metadata.MessageType) {
      case GithubWorkflowQueueMessageTypes.GithubWorkflowInProgress:
        DeserializeAndValidate<GithubWorkflowInProgressMessageData>(messageBody.Data);
        break;
      case GithubWorkflowQueueMessageTypes.GithubWorkflowCompleted:
        DeserializeAndValidate<GithubWorkflowCompletedMessageData>(messageBody.Data);
        break;
      default:
        throw new ValidationException($"Unsupported workflow queue message type '{messageBody.Metadata.MessageType}'.");
    }
  }

  private static T DeserializeAndValidate<T>(string json) where T : class {
    var model = System.Text.Json.JsonSerializer.Deserialize<T>(json);
    if (model == null) {
      throw new ValidationException("Message data is missing.");
    }

    Validator.ValidateObject(model, new ValidationContext(model), validateAllProperties: true);
    return model;
  }
}

public abstract class GithubWorkflowQueueMessageBase : IValidatableObject {
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
  public string Status { get; set; } = null!;

  [Required(AllowEmptyStrings = false)]
  public string WorkflowName { get; set; } = null!;

  public abstract IEnumerable<ValidationResult> Validate(ValidationContext validationContext);
}

public sealed class GithubWorkflowInProgressMessageData : GithubWorkflowQueueMessageBase {
  public override IEnumerable<ValidationResult> Validate(ValidationContext validationContext) {
    if (!string.Equals(Status, GithubWorkflowQueueStatuses.InProgress, StringComparison.OrdinalIgnoreCase)) {
      yield return new ValidationResult(
        $"Status must be '{GithubWorkflowQueueStatuses.InProgress}' for {GithubWorkflowQueueMessageTypes.GithubWorkflowInProgress} messages.",
        [nameof(Status)]);
    }
  }
}

public sealed class GithubWorkflowCompletedMessageData : GithubWorkflowQueueMessageBase {
  [Required(AllowEmptyStrings = false)]
  public string Conclusion { get; set; } = null!;

  public override IEnumerable<ValidationResult> Validate(ValidationContext validationContext) {
    if (!string.Equals(Status, GithubWorkflowQueueStatuses.Completed, StringComparison.OrdinalIgnoreCase)) {
      yield return new ValidationResult(
        $"Status must be '{GithubWorkflowQueueStatuses.Completed}' for {GithubWorkflowQueueMessageTypes.GithubWorkflowCompleted} messages.",
        [nameof(Status)]);
    }
  }
}