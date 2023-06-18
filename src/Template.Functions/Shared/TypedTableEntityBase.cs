using Azure;
using Azure.Data.Tables;

namespace Template.Functions.Shared;

public class TypedTableEntityBase : ITableEntity {
  public ETag ETag { get; set; }
  public string PartitionKey { get; set; } = null!;
  public string RowKey { get; set; } = null!;
  public DateTimeOffset? Timestamp { get; set; }
}