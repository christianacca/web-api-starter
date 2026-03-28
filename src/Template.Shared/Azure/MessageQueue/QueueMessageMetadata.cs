using System.ComponentModel.DataAnnotations;

namespace Template.Shared.Azure.MessageQueue; 

public class QueueMessageMetadata {
  [Required(AllowEmptyStrings = false)]
  public string MessageType { get; set; } = "";

  public ICollection<ClaimDto> UserContext { get; set; } = new List<ClaimDto>();
}