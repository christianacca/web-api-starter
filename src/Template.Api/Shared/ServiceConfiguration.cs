using System.Data;
using Hellang.Middleware.ProblemDetails;
using Microsoft.AspNetCore.Authentication.JwtBearer;
using Microsoft.AspNetCore.Cors.Infrastructure;
using Microsoft.EntityFrameworkCore;
using Microsoft.OpenApi.Models;
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
    var securitySchema = new OpenApiSecurityScheme {
      Description = "Using the Authorization header with the Bearer scheme.",
      Name = "Authorization",
      In = ParameterLocation.Header,
      Type = SecuritySchemeType.Http,
      Scheme = JwtBearerDefaults.AuthenticationScheme,
      Reference = new OpenApiReference {
        Type = ReferenceType.SecurityScheme, Id = JwtBearerDefaults.AuthenticationScheme
      }
    };

    c.AddSecurityDefinition(JwtBearerDefaults.AuthenticationScheme, securitySchema);

    c.AddSecurityRequirement(new OpenApiSecurityRequirement {
      { securitySchema, new[] { JwtBearerDefaults.AuthenticationScheme } }
    });
  }
}