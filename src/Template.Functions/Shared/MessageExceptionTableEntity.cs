namespace Template.Functions.Shared;

public class MessageExceptionTableEntity : TypedTableEntityBase {
  public string ExceptionMessage { get; set; } = "";
  public string ExceptionType { get; set; } = "";
  public string? StackTrace { get; set; }

  public static MessageExceptionTableEntity Create(Guid failedMessageId, Exception ex, string partitionKey = DefaultStoragePartitionKey) {
    return new MessageExceptionTableEntity {
      PartitionKey = partitionKey, 
      RowKey = failedMessageId.ToString(), 
      ExceptionMessage = ex.Message, 
      ExceptionType = ex.GetType().FullName ?? ex.GetType().Name,
      StackTrace = ex.StackTrace
    };
  }

  public const string DefaultStoragePartitionKey = "exception";
}