using Microsoft.EntityFrameworkCore;
using Template.Shared.Data.Mapping;
using Template.Shared.Model;

namespace Template.Shared.Data;

public class AppDatabase : DbContext {
  public AppDatabase(DbContextOptions<AppDatabase> options) : base(options) {
  }

  public DbSet<ExampleModel> Examples => Set<ExampleModel>();

  protected override void OnModelCreating(ModelBuilder modelBuilder) {
    modelBuilder.ApplyDefaultConventions();
    modelBuilder.ApplyConfigurationsFromAssembly(typeof(AppDatabase).Assembly);
  }
}