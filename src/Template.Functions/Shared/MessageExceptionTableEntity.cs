using System.Text.Json;

namespace Template.Functions.Shared;

public class MessageExceptionTableEntity : TypedTableEntityBase {
  public const string DefaultStoragePartitionKey = "exception";
  public const string DetailKey = "MessageDetailObject";

  public string? ExceptionDetail { get; set; }
  public string ExceptionMessage { get; set; } = "";
  public string ExceptionType { get; set; } = "";
  public string? StackTrace { get; set; }

  public T? GetExceptionDetailObject<T>() {
    return ExceptionDetail != null ? JsonSerializer.Deserialize<T>(ExceptionDetail) : default;
  }
  
  public static MessageExceptionTableEntity Create(Guid failedMessageId, Exception ex, string partitionKey = DefaultStoragePartitionKey) {
    var detail = ex.Data.Contains(DetailKey) ? ex.Data[DetailKey] : null;
    var serializedDetail = detail != null ? JsonSerializer.Serialize(detail) : null;
    return new MessageExceptionTableEntity {
      PartitionKey = partitionKey, 
      RowKey = failedMessageId.ToString(), 
      ExceptionDetail = serializedDetail,
      ExceptionMessage = ex.Message, 
      ExceptionType = ex.GetType().FullName ?? ex.GetType().Name,
      StackTrace = ex.StackTrace
    };
  }
}