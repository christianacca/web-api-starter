using Azure.Core;
using Azure.Core.Serialization;
using Azure.Identity;
using Microsoft.AspNetCore.Authentication.JwtBearer;
using Microsoft.AspNetCore.Hosting;
using Microsoft.Azure.Functions.Worker;
using Microsoft.Azure.Functions.Worker.Builder;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Azure;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Options;
using System.Text.Json;
using Template.Functions.GithubWorkflowOrchestrator;
using Template.Functions.Shared;
using Template.Functions.Shared.FunctionContextAccessor;
using Template.Functions.Shared.HttpContextAccessor;
using Template.Functions;
using Template.Shared.Azure.KeyVault;
using Template.Shared.Data;
using Template.Shared.Extensions;
using Template.Shared.Github;

var builder = FunctionsApplication.CreateBuilder(args);

builder.ConfigureFunctionsWebApplication();

builder.UseFunctionContextAccessor();

ConfigureAppConfiguration(builder.Configuration, builder.Environment);
ConfigureServices(builder.Services, builder.Configuration, builder.Environment);

var app = builder.Build();
await app.RunAsync();
return;

void ConfigureAppConfiguration(IConfigurationBuilder configuration, IHostEnvironment environment) {
  IConfigurationBuilder AddJsonFiles(IConfigurationBuilder configurationBuilder) {
    configurationBuilder
      .AddJsonFile("appsettings.json", optional: false, reloadOnChange: false)
      .AddJsonFile(
        $"appsettings.{environment.EnvironmentName}.json", optional: true, reloadOnChange: false
      );
    return configurationBuilder;
  }

  var initialConfigsBuilder = new ConfigurationBuilder().SetBasePath(environment.ContentRootPath);
  var initialConfigs = AddJsonFiles(initialConfigsBuilder).AddUserSecrets<Program>().Build();
  AddJsonFiles(configuration)
    .AddAzureKeyVault(initialConfigs, "InternalApi", includeSectionName: true)
    .AddUserSecrets<Program>();
}

void ConfigureServices(IServiceCollection services, IConfiguration configuration, IHostEnvironment environment) {

  services
    .AddFunctionContextAccessor()
    .AddFunctionHttpContextAccessor() // <- experimental equivalent to IHttpContextAccessor in ASP.NET Core
    .AddSingleton<ITokenValidator, UnsafeTrustedJwtSecurityTokenHandler>()
    .AddSingleton<GithubWorkflowQueueMessageProcessor>();

  // Authentication is required in the Functions project to enable HttpContext.User to be populated from EasyAuth's bearer 
  // token authentication in isolated-process mode. See UseAuthenticationStartupFilter for details.
  services
    .AddTransient<IStartupFilter, UseAuthenticationStartupFilter>()
    .AddAuthentication(JwtBearerDefaults.AuthenticationScheme)
    .AddJwtBearer(opts => {
      opts.TokenHandlers.Clear();
      opts.TokenHandlers.Add(new UnsafeTrustedJwtSecurityTokenHandler());
    });

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
  
  services.AddGithubServices("Github");

  if (environment.IsDevelopment()) {
    services.AddHostedService<DevelopmentQueueInitializer>();
  }

  ConfigureAzureClients(configuration, services, environment);

  // ensure that the same JsonSerializerOptions configuration is used for Durable Task Worker as in HttpTrigger functions
  services
    .Configure<WorkerOptions>(options => {
      var jsonOptions = new JsonSerializerOptions();
      jsonOptions.ConfigureStandardOptions();
      options.Serializer = new JsonObjectSerializer(jsonOptions);
    })
    .AddMvcCore(options => options.RemoveStringOutputFormatter())
    .AddJsonOptions(options => options.ConfigureStandardJsonOptions());
}

void ConfigureAzureClients(IConfiguration configuration, IServiceCollection services, IHostEnvironment environment) {
  services.AddAzureClientsCore(enableLogForwarding: true);
  services.AddAzureClients(cfg => {
    cfg.ConfigureDefaults(opts => { opts.Retry.Mode = RetryMode.Exponential; });

    cfg.UseCredential(sp => new DefaultAzureCredential(
      sp.GetRequiredService<IOptionsMonitor<DefaultAzureCredentialOptions>>().CurrentValue
    ));

    if (environment.IsDevelopment()) {
      cfg.AddQueueServiceClient(configuration.GetValue<string>("AzureWebJobsStorage") ?? "")
          .WithName(DevelopmentQueueInitializer.QueueClientName);
    }

    cfg.AddBlobServiceClient(configuration.GetSection("InternalApi:ReportBlobStorage"))
      .WithName("ReportStorageService");
  });
}