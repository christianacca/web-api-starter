using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Metadata.Builders;
using Template.Shared.Model;

namespace Template.Shared.Data.Mapping;

public class ServerInfoMap : IEntityTypeConfiguration<ServerInfo> {
  public void Configure(EntityTypeBuilder<ServerInfo> builder) {
    // ServerInfo is going to be populated from a raw sql query only
    // an alternative would be to map ServerInfo to a view
    builder.HasNoKey().ToTable(name: null);
  }
}