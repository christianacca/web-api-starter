namespace Template.Shared.Azure.MessageQueue;

public class MessageBody {
  public string Data { get; set; } = "";
  public Guid Id { get; set; } = Guid.NewGuid();
  public QueueMessageMetadata Metadata { get; set; } = new();
}