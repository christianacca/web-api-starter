using System.Text.Json.Serialization;
using Azure.Identity;
using Hellang.Middleware.ProblemDetails;
using Hellang.Middleware.ProblemDetails.Mvc;
using Microsoft.ApplicationInsights;
using Microsoft.AspNetCore.Authentication.JwtBearer;
using Microsoft.AspNetCore.Diagnostics;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Options;
using Mri.AppInsights.AspNetCore.Configuration;
using Serilog;
using Serilog.Events;
using Serilog.Formatting.Compact;
using Template.Api.Shared;
using Template.Api.Shared.AzureIdentity;
using Template.Api.Shared.Mvc;
using Template.Api.Shared.Proxy;
using Template.Shared.Data;

// ReSharper disable UnusedParameter.Local

Log.Logger = new LoggerConfiguration()
  .WriteTo.Console(new CompactJsonFormatter())
  .CreateBootstrapLogger();

Log.Information("Starting web host");

try {
  var builder = WebApplication.CreateBuilder(args);

  builder.WebHost.UseKestrel(o => o.AddServerHeader = false);
  // ConfigureConfiguration(builder.Configuration);
  ConfigureLogging(builder.Host);
  ConfigureServices(builder.Services, builder.Configuration, builder.Environment);

  var app = builder.Build();

  await using (var scope = app.Services.CreateAsyncScope()) {
    ConfigureMiddleware(app, scope.ServiceProvider, app.Environment);
    ConfigureEndpoints(app, scope.ServiceProvider);
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


void ConfigureLogging(IHostBuilder host) {
  // IMPORTANT: the configs here and in appsettings.json for Serilog is specifically designed so that we're NOT logging
  // to the console AND we're suppressing most log entries created by ASP.NET
  // This is to avoid duplicating App Insights telemetry and what is sent to Azure Container Insights (via console)
  // Therefore be VERY careful in changing this logging configuration, otherwise cost of logging in Azure will likely
  // be high at no benefit
  host.UseSerilog((context, services, loggerConfiguration) => {
    loggerConfiguration
      .MinimumLevel.Override("Template.Api", LogEventLevel.Information)
      .MinimumLevel.Override(typeof(ProblemDetailsMiddleware).Namespace, LogEventLevel.Warning)
      .MinimumLevel.Override(typeof(DeveloperExceptionPageMiddleware).Namespace, LogEventLevel.Warning)
      .ReadFrom.Configuration(context.Configuration)
      .Enrich.FromLogContext()
      .ReadFrom.Services(services)
      .WriteTo.ApplicationInsights(services.GetRequiredService<TelemetryClient>(), TelemetryConverter.Traces);
    if (context.HostingEnvironment.IsDevelopment()) {
      loggerConfiguration.WriteTo.Console();
    } else {
      // we HAVE to log to the console to capture exceptions that occur during startup as other sinks (eg App Insights)
      // might not have been configured at the point when the exception occurred
      loggerConfiguration.WriteTo.Console(new CompactJsonFormatter(), LogEventLevel.Fatal);
    }
  });
}

void ConfigureServices(IServiceCollection services, IConfiguration configuration, IHostEnvironment environment) {
  services.AddHttpContextAccessor();

  services.AddDbContext<AppDatabase>(options => {
    options.UseSqlServer(configuration.GetDefaultConnectionString());
    if (environment.IsDevelopment()) {
      options.EnableSensitiveDataLogging();
    }
  });

  services
    .AddProblemDetails(ServiceConfiguration.ConfigureProblemDetails)
    .AddProblemDetailsConventions();

  services.AddControllers(o => {
    // tweaks to built-in non-success http responses
    o.Conventions.Add(new NotFoundResultApiConvention());
  }).AddJsonOptions(o => o.JsonSerializerOptions.ReferenceHandler = ReferenceHandler.IgnoreCycles);;

  services.AddCors(ServiceConfiguration.ConfigureCors);

  services.AddHealthChecks();

  // Learn more about configuring Swagger/OpenAPI at https://aka.ms/aspnetcore/swashbuckle
  services.AddEndpointsApiExplorer();
  services.AddSwaggerGen(ServiceConfiguration.ConfigureSwagger);

  services
    .AddAuthentication(JwtBearerDefaults.AuthenticationScheme)
    .AddJwtBearer(options => {
      options.MapInboundClaims = false;
      configuration.GetSection("Api:TokenProvider").Bind(options);
    });

  ConfigureAzureIdentityServices();
  ConfigureProxyServices();

  var aiSettings = configuration.GetSection("ApplicationInsights").Get<ApplicationInsightsSettings>();
  aiSettings.CloudRoleName = "DSG API";
  services.AddAppInsights(aiSettings);


  void ConfigureAzureIdentityServices() {
    services.AddSingleton<TokenServiceFactory>();
    services.AddSingleton<TokenServiceSelector>(provider => (optionsName, audience, credentialOptions) => {
      if (environment.IsDevelopment()) {
        return new FakeTokenService();
      } else {
        return new CachedTokenService(audience, credentialOptions);
      }
    });

    services.AddOptions<DefaultAzureCredentialOptions>().BindConfiguration("Api:DefaultAzureCredentials");

    services
      .AddOptions<TokenRequestOptions>(Options.DefaultName)
      .BindConfiguration("Api:FunctionsAppToken")
      .ValidateDataAnnotations();
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
    services
      .AddHttpClient<FunctionAppHttpClient>(client => {
        var baseUrl =
          configuration.GetValue<string>("Api:ReverseProxy:Clusters:FunctionsApp:Destinations:Primary:Address");
        client.BaseAddress = new Uri(baseUrl);
      })
      .AddHttpMessageHandler<HeaderForwardingHttpClientHandler>()
      .AddHttpMessageHandler<AzureIdentityAuthHttpClientHandler>();
  }
}

void ConfigureMiddleware(IApplicationBuilder app, IServiceProvider services, IHostEnvironment environment) {
  app.UseProblemDetails();

  if (environment.IsDevelopment()) {
    // note: the proxy is currently causing the requests for swagger ui to require authentication
    // workaround: comment out `app.MapReverseProxy();` below
    app.UseSwagger();
    app.UseSwaggerUI();
  }

  app.UseCors(); // critical: this MUST be before UseAuthentication and UseAuthorization

  app.UseAuthentication();
  app.UseAuthorization();

  app.UseAppInsightsSampling();

  app.UseWhen(ctx => !ctx.IsProxiedRequest(), app2 => {
    // middleware that only runs for http requests that are NOT being proxied
    // app2.UseXxx();
  });
}

void ConfigureEndpoints(IEndpointRouteBuilder app, IServiceProvider services) {
  app.MapControllers().RequireAuthorization();
  app.MapHealthChecks("/health");
  app.MapReverseProxy();
}

async Task MigrateDbAsync(IServiceProvider services, IHostEnvironment environment) {
  if (!environment.IsDevelopment()) return;

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
