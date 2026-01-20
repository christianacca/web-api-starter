using Azure.Core;
using Azure.Identity;
using Microsoft.Azure.Functions.Worker;
using Microsoft.Azure.Functions.Worker.Builder;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Azure;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Options;
using Template.Functions.Shared;
using Template.Functions.Shared.FunctionContextAccessor;
using Template.Functions.Shared.HttpContextAccessor;
using Template.Shared.Azure.KeyVault;
using Template.Shared.Data;

var builder = FunctionsApplication.CreateBuilder(args);

builder.ConfigureFunctionsWebApplication();

builder.UseFunctionContextAccessor();

ConfigureAppConfiguration(builder.Configuration, builder.Environment);
ConfigureServices(builder.Services, builder.Configuration, builder.Environment);
ConfigureLogging(builder.Logging);

var app = builder.Build();
await app.RunAsync();
return;

void ConfigureAppConfiguration(IConfigurationBuilder configuration, IHostEnvironment environment) {
  var initialConfigs = configuration.Build();
  configuration
    .AddAzureKeyVault(initialConfigs, "InternalApi", includeSectionName: true);
}

void ConfigureServices(IServiceCollection services, IConfiguration configuration, IHostEnvironment environment) {
  services
    .AddFunctionContextAccessor()
    .AddFunctionHttpContextAccessor() // <- experimental equivalent to IHttpContextAccessor in ASP.NET Core
    .AddSingleton<ITokenValidator, UnsafeTrustedJwtSecurityTokenHandler>();

  services.AddApplicationInsightsTelemetryWorkerService();
  services.ConfigureFunctionsApplicationInsights();

  services.AddDbContext<AppDatabase>(options => {
    var internalApiConfig = configuration.GetSection("InternalApi");
    options.UseSqlServer(internalApiConfig.GetDefaultConnectionString(), sqlOptions =>
      sqlOptions.EnableRetryOnFailure(
        maxRetryCount: 3,
        maxRetryDelay: TimeSpan.FromSeconds(10),
        errorNumbersToAdd: null)
    );
    if (environment.IsDevelopment()) {
      options.EnableSensitiveDataLogging();
    }
  });

  services.AddEnvironmentInfoOptions(environment.IsDevelopment());

  ConfigureAzureClients(configuration, services);
}

void ConfigureAzureClients(IConfiguration configuration, IServiceCollection services) {
  services.AddAzureClientsCore(enableLogForwarding: true);
  services.AddAzureClients(cfg => {
    cfg.ConfigureDefaults(opts => { opts.Retry.Mode = RetryMode.Exponential; });

    cfg.UseCredential(sp => new DefaultAzureCredential(
      sp.GetRequiredService<IOptionsMonitor<DefaultAzureCredentialOptions>>().CurrentValue
    ));

    cfg.AddBlobServiceClient(configuration.GetSection("InternalApi:ReportBlobStorage"))
      .WithName("ReportStorageService");
  });
}

void ConfigureLogging(ILoggingBuilder logging) {
  logging.Services.Configure<LoggerFilterOptions>(options => {
    var defaultRule = options.Rules
      .FirstOrDefault(r =>
        r.ProviderName == "Microsoft.Extensions.Logging.ApplicationInsights.ApplicationInsightsLoggerProvider");
    if (defaultRule is not null) {
      options.Rules.Remove(defaultRule);
    }
  });
}