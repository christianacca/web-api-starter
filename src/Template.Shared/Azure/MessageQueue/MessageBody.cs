namespace Template.Shared.Azure.MessageQueue;

public class MessageBody {
  public string Data { get; set; } = "";
  public Guid Id { get; set; } = new();
  public QueueMessageMetadata Metadata { get; set; } = new();
}