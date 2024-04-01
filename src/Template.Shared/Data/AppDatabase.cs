using Microsoft.EntityFrameworkCore;
using Template.Shared.Data.Mapping;
using Template.Shared.Model;

namespace Template.Shared.Data;

public class AppDatabase : DbContext {
  public AppDatabase(DbContextOptions<AppDatabase> options) : base(options) {
  }

  public DbSet<ExampleModel> Examples => Set<ExampleModel>();
  public DbSet<IdentityPrincipal> Identities => Set<IdentityPrincipal>();
  public DbSet<UserPrincipal> Users => Set<UserPrincipal>();
  public DbSet<OrganisationPrincipal> Organisations => Set<OrganisationPrincipal>();
  public DbSet<GroupPrincipal> Groups => Set<GroupPrincipal>();

  protected override void ConfigureConventions(ModelConfigurationBuilder configurationBuilder) {
    configurationBuilder.ApplyDefaultConventions();
  }
  
  protected override void OnModelCreating(ModelBuilder modelBuilder) {
    modelBuilder.ApplyConfigurationsFromAssembly(typeof(AppDatabase).Assembly);
  }
}