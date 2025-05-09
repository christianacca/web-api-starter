using System.Reflection;
using System.Text.Json.Serialization;
using Azure.Core;
using Azure.Identity;
using Hellang.Middleware.ProblemDetails;
using Hellang.Middleware.ProblemDetails.Mvc;
using Microsoft.ApplicationInsights;
using Microsoft.AspNetCore.Authentication.JwtBearer;
using Microsoft.AspNetCore.Diagnostics;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Azure;
using Microsoft.Extensions.Options;
using Microsoft.IdentityModel.JsonWebTokens;
using Mri.AppInsights.AspNetCore.Configuration;
using Mri.Azure.ManagedIdentity;
using Serilog;
using Serilog.Events;
using Serilog.Formatting.Compact;
using Template.Api.Shared;
using Template.Api.Shared.ExceptionHandling;
using Template.Api.Shared.Mvc;
using Template.Api.Shared.Proxy;
using Template.Shared.Azure.KeyVault;
using Template.Shared.Data;
using Template.Shared.Util;

// ReSharper disable UnusedParameter.Local

var consoleOnlyLogger = new LoggerConfiguration().WriteTo.Console(new CompactJsonFormatter()).CreateLogger();
Log.Logger = new LoggerConfiguration().WriteTo.Console(new CompactJsonFormatter()).CreateBootstrapLogger();

Log.Information("Starting web host");

try {
  var builder = WebApplication.CreateBuilder(args);

  builder.WebHost.UseKestrel(o => o.AddServerHeader = false);
  ConfigureConfiguration(builder.Configuration, builder.Environment);
  ConfigureLogging(builder.Host);
  ConfigureServices(builder.Services, builder.Configuration, builder.Environment);

  var app = builder.Build();

  await using (var scope = app.Services.CreateAsyncScope()) {
    ConfigureMiddleware(app, scope.ServiceProvider, app.Environment);
    await MigrateDbAsync(scope.ServiceProvider, app.Environment);
  }

  app.Run();
}
catch (Exception ex) {
  // note: you may find an exception HostingListener+StopTheHostException thrown when running ef migrations tooling
  // at the command line (EG `dotnet ef migrations add xxx`)
  // this can be safely ignored as this is intentional exception thrown in .net 6 (quirky but true)
  Log.Fatal(ex, "Host terminated unexpectedly");
}
finally {
  Log.Information("Shut down complete");
  Log.CloseAndFlush();
}

void ConfigureConfiguration(ConfigurationManager configuration, IHostEnvironment environment) {
  if (!EF.IsDesignTime) {
    configuration.AddAzureKeyVault(configuration, "Api", includeSectionName: true);
  }
}

void ConfigureLogging(IHostBuilder host) {
  // IMPORTANT: the configs here and in appsettings.json for Serilog is specifically designed so that we're NOT logging
  // to the console AND we're suppressing most log entries created by ASP.NET
  // This is to avoid duplicating App Insights telemetry and what is sent to Azure Container Insights (via console)
  // Therefore be VERY careful in changing this logging configuration, otherwise cost of logging in Azure will likely
  // be high at no benefit
  host.UseSerilog((context, services, loggerConfiguration) => {
    // note: to disable appinsights logging (for example to send logs to stdout only) either:
    // - change the value ApplicationInsights:Enable directly in appsettings.json OR
    // - set an environment variable in the host (eg container app): ApplicationInsights__Enable=false
    var appInsights = context.Configuration.GetSection("ApplicationInsights").Get<ApplicationInsightsSettings>();
    if (context.HostingEnvironment.IsDevelopment()) {
      loggerConfiguration.WriteTo.Console();
    } else {
      // at minimum we HAVE to log to the *console* to capture exceptions that occur during startup as other sinks (eg App Insights)
      // might not have been configured at the point when the exception occurred
      var logLevel = appInsights?.IsDisabled == true ? LogEventLevel.Information : LogEventLevel.Fatal;
      if (appInsights?.IsDisabled == true) {
        consoleOnlyLogger.Information("Application Insights is disabled, falling back to sending '{LogLevel}' level logs to stdout", logLevel);
      } else {
        consoleOnlyLogger.Information("Application Insights is enabled, only sending '{LogLevel}' level logs to stdout", logLevel);
      }
      loggerConfiguration.WriteTo.Console(new CompactJsonFormatter(), logLevel);
    }

    loggerConfiguration
      .MinimumLevel.Override("Template.Api", LogEventLevel.Information)
      .MinimumLevel.Override("Microsoft.Hosting.Lifetime", LogEventLevel.Information)
      .MinimumLevel.Override(typeof(TokenServiceFactory).Namespace ?? "", LogEventLevel.Information)
      .MinimumLevel.Override(typeof(ProblemDetailsMiddleware).Namespace ?? "", LogEventLevel.Warning)
      .MinimumLevel.Override(typeof(DeveloperExceptionPageMiddleware).Namespace ?? "", LogEventLevel.Warning)
      .ReadFrom.Configuration(context.Configuration)
      .Enrich.FromLogContext()
      .ReadFrom.Services(services)
      .WriteTo.ApplicationInsights(services.GetRequiredService<TelemetryClient>(), TelemetryConverter.Traces);
  });
}

void ConfigureServices(IServiceCollection services, IConfiguration configuration, IHostEnvironment environment) {
  services.AddHttpContextAccessor();

  services.AddDbContext<AppDatabase>(options => {
    options.UseSqlServer(configuration.GetSection("Api").GetDefaultConnectionString(), sqlOptions =>
      sqlOptions.EnableRetryOnFailure(
        maxRetryCount: 3,
        maxRetryDelay: TimeSpan.FromSeconds(10),
        errorNumbersToAdd: null)
    );
    if (environment.IsDevelopment()) {
      options.EnableSensitiveDataLogging();
    }
  });

  services
    .AddProblemDetails(ProblemDetailsConfigurator.ConfigureProblemDetails)
    .AddProblemDetailsConventions();

  services.AddControllers(o => {
    // tweaks to built-in non-success http responses
    o.Conventions.Add(new NotFoundResultApiConvention());
  }).AddJsonOptions(o => o.JsonSerializerOptions.ReferenceHandler = ReferenceHandler.IgnoreCycles);

  services.AddCors(ServiceConfiguration.ConfigureCors);

  services.AddHealthChecks();

  // Learn more about configuring Swagger/OpenAPI at https://aka.ms/aspnetcore/swashbuckle
  services.AddEndpointsApiExplorer();
  services.AddSwaggerGen(ServiceConfiguration.ConfigureSwagger);

  services
    .AddAuthentication(JwtBearerDefaults.AuthenticationScheme)
    .AddJwtBearer(options => {
      options.TokenValidationParameters.NameClaimType = JwtRegisteredClaimNames.Sub;
      options.MapInboundClaims = false;
      configuration.GetSection("Api:TokenProvider").Bind(options);
    });

  ConfigureAzureClients();
  ConfigureAzureIdentityServices();
  ConfigureProxyServices();
  
  services.AddEnvironmentInfoOptions(environment.IsDevelopment());

  var aiSettings = configuration.GetSection("ApplicationInsights").Get<ApplicationInsightsSettings>();
  if (aiSettings != null) {
    aiSettings.CloudRoleName = "API";
    aiSettings.AuthenticatedUserNameClaimTypes = new List<string> { JwtRegisteredClaimNames.Sub };
    aiSettings.ApplicationVersion =
      ProductVersion.GetFromAssemblyInformation(Assembly.GetExecutingAssembly())?.ToString();
    aiSettings.ExcludeDataCancellationException = true; // our api considers cancellations to be handled successfully
    services.AddAppInsights(aiSettings);
  }

  void ConfigureAzureClients() {

    services.AddAzureClientsCore(enableLogForwarding: true);
    services.AddAzureClients(cfg => {
      // see: https://github.com/Azure/azure-sdk-for-net/blob/Microsoft.Extensions.Azure_1.4.0/sdk/extensions/Microsoft.Extensions.Azure/README.md

      cfg.ConfigureDefaults(opts => { opts.Retry.Mode = RetryMode.Exponential; });

      cfg.UseCredential(sp => new DefaultAzureCredential(
        sp.GetRequiredService<IOptionsMonitor<DefaultAzureCredentialOptions>>().CurrentValue
      ));

      cfg.AddQueueServiceClient(configuration.GetSection("Api:FunctionsAppQueue"))
        .WithName("FunctionsDefaultQueueClient");
    });
  }

  void ConfigureAzureIdentityServices() {
    services
      .AddAzureManagedIdentityToken(options => {
        options.TokenServiceSelector = (optionsName, audience, credentialOptions, _) => {
          return optionsName switch {
            TokenOptionNames.FunctionApp when environment.IsDevelopment() => new FakeTokenService(),
            _ => new DefaultTokenService(audience, credentialOptions)
          };
        };
        options.DefaultAzureCredentialsConfigurationSectionName = "Api:DefaultAzureCredentials";
      })
      .AddAzureManagedIdentityTokenOption(TokenOptionNames.FunctionApp, "Api:FunctionsAppToken");
  }

  void ConfigureProxyServices() {
    services.AddReverseProxy()
      .LoadFromConfig(configuration.GetSection("Api:ReverseProxy"))
      .AddTransforms<TokenAuthenticationTransform>();


    services
      .AddTransient<AzureIdentityAuthHttpClientHandler>()
      .AddTransient<HeaderForwardingHttpClientHandler>();

    // NOTE: this strongly typed HttpClient is NOT used by the YARP reverse proxy
    // Instead FunctionAppHttpClient is when you meed to make calls to the Functions app directly, say from your Controller
    services.AddProxyHttpClient<FunctionAppHttpClient>(
      configuration.GetValue<string>("Api:ReverseProxy:Clusters:FunctionsApp:Destinations:Primary:Address") ?? "",
      TokenOptionNames.FunctionApp
    );
  }
}

void ConfigureMiddleware(IApplicationBuilder app, IServiceProvider services, IHostEnvironment environment) {
  app.UseProblemDetails();

  if (environment.IsDevelopment()) {
    app.UseSwagger();
    app.UseSwaggerUI();
  }
  
  app.UseMiddleware<ApiVsResponseHeaderMiddleware>();

  app.UseRouting();
  
  app.UseCors(); // critical: this MUST be before UseAuthentication and UseAuthorization

  app.UseAuthentication();
  app.UseAuthorization();

  app.UseAppInsightsSampling();

  app.UseWhen(ctx => !IsProxiedRequest(ctx), _ => {
    // middleware that only runs for http requests that are NOT being proxied
    // app2.UseXxx();
  });
  
  app.UseEndpoints(endpoints => {
    endpoints.MapControllers().RequireAuthorization();
    endpoints.MapHealthChecks("/health");
    endpoints.MapReverseProxy();
  });
}

async Task MigrateDbAsync(IServiceProvider services, IHostEnvironment environment) {
  if (!environment.IsDevelopment() || EF.IsDesignTime) return;

  Log.Logger.Warning("Developer mode detected... running database migrations");
  try {
    var context = services.GetRequiredService<AppDatabase>();
    await context.Database.MigrateAsync();
  }
  catch (Exception ex) {
    Log.Logger.Error(ex, "An error occurred while migrating the database");
    throw;
  }
}


bool IsProxiedRequest(HttpContext context) => context.IsProxiedRequest();