using System.Data;
using Hellang.Middleware.ProblemDetails;
using Microsoft.AspNetCore.Authentication.JwtBearer;
using Microsoft.AspNetCore.Cors.Infrastructure;
using Microsoft.EntityFrameworkCore;
using Microsoft.OpenApi.Models;
using Swashbuckle.AspNetCore.SwaggerGen;

namespace Template.Api.Shared;

public static class ServiceConfiguration {
  public static void ConfigureCors(CorsOptions o) {
    o.AddDefaultPolicy(builder => {
      builder.AllowAnyOrigin()
        .AllowAnyHeader()
        // required by app-insights for distributed tracing
        .WithExposedHeaders("Request-Id", "Request-Context")
        .AllowAnyMethod();
    });
  }

  public static void ConfigureProblemDetails(ProblemDetailsOptions c) {
    c.ValidationProblemStatusCode = StatusCodes.Status400BadRequest; // default is a 422
    c.MapToStatusCode<DBConcurrencyException>(StatusCodes.Status409Conflict);
    c.MapToStatusCode<DbUpdateConcurrencyException>(StatusCodes.Status409Conflict);
    c.MapToStatusCode<NotImplementedException>(StatusCodes.Status501NotImplemented);
    // note: we're overriding the default `IsProblem` from the library because YARP is setting the content-length
    // header for a 404 which causes ProblemDetailsMiddleware to NOT return the ProblemDetails response that we want
    c.IsProblem = context => ProblemDetailsOptionsSetup.IsProblemStatusCode(context.Response.StatusCode);
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