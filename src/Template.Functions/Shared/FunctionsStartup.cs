using System.IO;
using Microsoft.Azure.Functions.Extensions.DependencyInjection;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Template.Functions.Shared;
using Template.Shared.Data;

[assembly: FunctionsStartup(typeof(Startup))]

namespace Template.Functions.Shared;

public class Startup : FunctionsStartup {
  public override void ConfigureAppConfiguration(IFunctionsConfigurationBuilder builder) {
    FunctionsHostBuilderContext context = builder.GetContext();

    builder.ConfigurationBuilder
      .AddJsonFile(Path.Combine(context.ApplicationRootPath, "appsettings.json"), optional: false, reloadOnChange: false)
      .AddJsonFile(Path.Combine(context.ApplicationRootPath, $"appsettings.{context.EnvironmentName}.json"), optional: true, reloadOnChange: false)
      .AddEnvironmentVariables();
  }

  public override void Configure(IFunctionsHostBuilder builder) {
    builder.Services.AddSingleton<ITokenValidator, UnsafeTrustedJwtSecurityTokenHandler>();
    builder.Services.AddDbContext<AppDatabase>(options => {
      var ctx = builder.GetContext();
      var configuration = ctx.Configuration;
      options.UseSqlServer(configuration.GetDefaultConnectionString());
      if (ctx.EnvironmentName == "Development") {
        options.EnableSensitiveDataLogging();
      }
    });
  }
}