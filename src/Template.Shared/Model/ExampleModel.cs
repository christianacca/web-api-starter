using System.ComponentModel.DataAnnotations;

namespace Template.Shared.Model;

public class ExampleModel {
  /// <remarks>
  /// Using GUID to open up more options when creating new entities (eg: fully creating an an entity whilst
  /// offline/disconnected from the server).
  /// EF Core will generate sequential guids in the db to avoid index fragmentation
  /// </remarks>
  public Guid Id { get; set; }

  public string Address { get; set; } = "";

  public DateTime DateOfBirth { get; set; }

  public string Title { get; set; } = "";

  [MinLength(1, ErrorMessage = ErrorMessageConstants.NonEmptyStringRequired), MaxLength(100)]
  public string FirstName { get; set; } = "";

  [MinLength(1, ErrorMessage = ErrorMessageConstants.NonEmptyStringRequired), MaxLength(100)]
  public string LastName { get; set; } = "";
}