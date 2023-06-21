namespace Template.Shared.Azure.MessageQueue; 

public class QueueMessageMetadata {
  public string MessageType { get; set; } = "";
  public ICollection<ClaimDto> UserContext { get; set; } = new List<ClaimDto>();
}