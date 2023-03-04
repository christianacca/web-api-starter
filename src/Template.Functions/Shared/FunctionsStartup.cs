using Azure.Core;
using Azure.Identity;
using Microsoft.Azure.Functions.Extensions.DependencyInjection;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Azure;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Options;
using Template.Functions.Shared;
using Template.Shared.Azure.KeyVault;
using Template.Shared.Data;

[assembly: FunctionsStartup(typeof(Startup))]

namespace Template.Functions.Shared;


public class Startup : FunctionsStartup {
  public override void ConfigureAppConfiguration(IFunctionsConfigurationBuilder builder) {
    FunctionsHostBuilderContext context = builder.GetContext();

    IConfigurationBuilder AddJsonFiles(IConfigurationBuilder configurationBuilder) {
      configurationBuilder
        .AddJsonFile(
          Path.Combine(context.ApplicationRootPath, "appsettings.json"), optional: false, reloadOnChange: false
        )
        .AddJsonFile(
          Path.Combine(context.ApplicationRootPath, $"appsettings.{context.EnvironmentName}.json"),
          optional: true, reloadOnChange: false
        );
      return configurationBuilder;
    }

    var initialConfigs = AddJsonFiles(new ConfigurationBuilder()).Build();
    AddJsonFiles(builder.ConfigurationBuilder)
      .AddAzureKeyVault(initialConfigs.GetSection("InternalApi"))
      .AddEnvironmentVariables();
  }

  public override void Configure(IFunctionsHostBuilder builder) {

    builder.Services
      .AddHttpContextAccessor()
      .AddSingleton<ITokenValidator, UnsafeTrustedJwtSecurityTokenHandler>();

    builder.Services.AddDbContext<AppDatabase>(options => {
      var ctx = builder.GetContext();
      var configuration = ctx.Configuration.GetSection("InternalApi");
      options.UseSqlServer(configuration.GetDefaultConnectionString(), sqlOptions => sqlOptions.EnableRetryOnFailure(
        maxRetryCount: 3,
        maxRetryDelay: TimeSpan.FromSeconds(10),
        errorNumbersToAdd: null)
      );
      if (ctx.EnvironmentName == "Development") {
        options.EnableSensitiveDataLogging();
      }
    });

    ConfigureAzureClients(builder);
  }

  void ConfigureAzureClients(IFunctionsHostBuilder builder) {

    builder.Services.AddAzureClientsCore(enableLogForwarding: true);
    builder.Services.AddAzureClients(cfg => {
      // see: https://github.com/Azure/azure-sdk-for-net/blob/Microsoft.Extensions.Azure_1.4.0/sdk/extensions/Microsoft.Extensions.Azure/README.md

      cfg.ConfigureDefaults(opts => { opts.Retry.Mode = RetryMode.Exponential; });

      cfg.UseCredential(sp => new DefaultAzureCredential(
        sp.GetRequiredService<IOptionsMonitor<DefaultAzureCredentialOptions>>().CurrentValue
      ));

      cfg.AddBlobServiceClient(builder.GetContext().Configuration.GetSection("InternalApi:ReportBlobStorage"))
       .WithName("ReportStorageService");
    });
  }
}