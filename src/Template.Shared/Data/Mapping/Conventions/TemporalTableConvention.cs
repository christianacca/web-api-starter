using Microsoft.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore.Metadata.Builders;
using Microsoft.EntityFrameworkCore.Metadata.Conventions;

namespace Template.Shared.Data.Mapping.Conventions;

public class TemporalTableConvention : IModelFinalizingConvention {
  public void ProcessModelFinalizing(
    IConventionModelBuilder modelBuilder,
    IConventionContext<IConventionModelBuilder> context
  ) {
    var entityTypes = modelBuilder.Metadata.GetEntityTypes()
      .Where(t => !t.IsKeyless && !t.IsOwned() && t.BaseType == null);

    // Enable Temporal table support (a more powerful and simpler way of implementing soft deletes)
    foreach (var entityType in entityTypes) {
      entityType.SetIsTemporal(true);
    }
  }
}