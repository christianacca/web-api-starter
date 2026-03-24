using System.ComponentModel.DataAnnotations;

namespace Template.Shared.Azure.MessageQueue;

public class MessageBody : IValidatableObject {
  [Required(AllowEmptyStrings = false)]
  public string Data { get; set; } = "";

  public Guid Id { get; set; } = Guid.NewGuid();

  [Required]
  public QueueMessageMetadata Metadata { get; set; } = new();

  public IEnumerable<ValidationResult> Validate(ValidationContext validationContext) {
    if (Metadata == null) {
      yield break;
    }

    var nestedResults = new List<ValidationResult>();
    var isValid = Validator.TryValidateObject(Metadata, new ValidationContext(Metadata), nestedResults, validateAllProperties: true);

    if (isValid) {
      yield break;
    }

    foreach (var validationResult in nestedResults) {
      yield return validationResult;
    }
  }
}