using Microsoft.AspNetCore.Authentication.JwtBearer;
using Microsoft.AspNetCore.Cors.Infrastructure;
using Microsoft.OpenApi;
using Swashbuckle.AspNetCore.SwaggerGen;
using Template.Api.Shared.Mvc;

namespace Template.Api.Shared;

public static class ServiceConfiguration {
  public static void ConfigureCors(CorsOptions o) {
    o.AddDefaultPolicy(builder => {
      builder.AllowAnyOrigin()
        .AllowAnyHeader()
        // required by app-insights for distributed tracing
        .WithExposedHeaders("Request-Id", "Request-Context")
        // required to track cloudflare information
        .WithExposedHeaders("cf-cache-status", "cf-mitigated")
        .WithExposedHeaders(ApiVsResponseHeaderMiddleware.ApiVersionHeaderName)
        .AllowAnyMethod();
    });
  }

  public static void ConfigureSwagger(SwaggerGenOptions c) {
    c.SwaggerDoc("v1", new OpenApiInfo { 
      Title = "Template.Api", 
      Version = "v1" 
    });
    
    c.AddSecurityDefinition(JwtBearerDefaults.AuthenticationScheme, new OpenApiSecurityScheme {
      Description = "Using the Authorization header with the Bearer scheme.",
      Name = "Authorization",
      In = ParameterLocation.Header,
      Type = SecuritySchemeType.Http,
      Scheme = JwtBearerDefaults.AuthenticationScheme
    });

    c.AddSecurityRequirement(document => new OpenApiSecurityRequirement {
      [new OpenApiSecuritySchemeReference(JwtBearerDefaults.AuthenticationScheme, document)] = []
    });
  }
}