using Azure.Core;
using Azure.Identity;
using Microsoft.Azure.Functions.Worker;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Azure;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Options;
using Template.Functions.Shared;
using Template.Shared.Azure.KeyVault;
using Template.Shared.Data;

namespace Template.Functions;

internal class Program {
  private static async Task Main(/*string[] args*/) {
    var host = new HostBuilder()
      .ConfigureAppConfiguration((hostContext, configuration) => {
        IConfigurationBuilder AddJsonFiles(IConfigurationBuilder configurationBuilder) {
          configurationBuilder
            .AddJsonFile("appsettings.json", optional: false, reloadOnChange: false)
            .AddJsonFile(
              $"appsettings.{hostContext.HostingEnvironment.EnvironmentName}.json", optional: true,
              reloadOnChange: false
            );
          return configurationBuilder;
        }

        var initialConfigsBuilder =
          new ConfigurationBuilder().SetBasePath(hostContext.HostingEnvironment.ContentRootPath);
        var initialConfigs = AddJsonFiles(initialConfigsBuilder).AddUserSecrets<Program>().Build();
        AddJsonFiles(configuration)
          .AddAzureKeyVault(initialConfigs.GetSection("InternalApi"))
          .AddUserSecrets<Program>();
      })
      .ConfigureFunctionsWebApplication()
      .ConfigureServices((context, services) => {
        services
          .AddHttpContextAccessor()
          .AddSingleton<ITokenValidator, UnsafeTrustedJwtSecurityTokenHandler>();

        services.AddApplicationInsightsTelemetryWorkerService();
        services.ConfigureFunctionsApplicationInsights();

        services.AddDbContext<AppDatabase>(options => {
          var configuration = context.Configuration.GetSection("InternalApi");
          options.UseSqlServer(configuration.GetDefaultConnectionString(), sqlOptions =>
            sqlOptions.EnableRetryOnFailure(
              maxRetryCount: 3,
              maxRetryDelay: TimeSpan.FromSeconds(10),
              errorNumbersToAdd: null)
          );
          if (context.HostingEnvironment.IsDevelopment()) {
            options.EnableSensitiveDataLogging();
          }
        });

        ConfigureAzureClients(context, services);
      }).ConfigureLogging(logging => {
        logging.Services.Configure<LoggerFilterOptions>(options => {
          // remove the default rule to capture information level logs in Application Insights
          var defaultRule = options.Rules
            .FirstOrDefault(r => r.ProviderName == "Microsoft.Extensions.Logging.ApplicationInsights.ApplicationInsightsLoggerProvider");
          if (defaultRule is not null) {
            options.Rules.Remove(defaultRule);
          }
        });
      })
      .Build();

    await host.RunAsync();
  }

  private static void ConfigureAzureClients(HostBuilderContext context, IServiceCollection services) {
    services.AddAzureClientsCore(enableLogForwarding: true);
    services.AddAzureClients(cfg => {
      // see: https://github.com/Azure/azure-sdk-for-net/blob/Microsoft.Extensions.Azure_1.4.0/sdk/extensions/Microsoft.Extensions.Azure/README.md

      cfg.ConfigureDefaults(opts => { opts.Retry.Mode = RetryMode.Exponential; });

      cfg.UseCredential(sp => new DefaultAzureCredential(
        sp.GetRequiredService<IOptionsMonitor<DefaultAzureCredentialOptions>>().CurrentValue
      ));

      cfg.AddBlobServiceClient(context.Configuration.GetSection("InternalApi:ReportBlobStorage"))
        .WithName("ReportStorageService");
    });
  }
}