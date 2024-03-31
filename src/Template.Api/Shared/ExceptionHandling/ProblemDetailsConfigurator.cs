using System.Data;
using Hellang.Middleware.ProblemDetails;
using Microsoft.EntityFrameworkCore;
using Template.Api.Shared.Mvc;
using ProblemDetailsOptions = Hellang.Middleware.ProblemDetails.ProblemDetailsOptions;

namespace Template.Api.Shared.ExceptionHandling; 

public static class ProblemDetailsConfigurator {
  public static void ConfigureProblemDetails(ProblemDetailsOptions c) {
    c.ValidationProblemStatusCode = StatusCodes.Status400BadRequest; // default is a 422
    c.MapToStatusCode<DBConcurrencyException>(StatusCodes.Status409Conflict);
    c.MapToStatusCode<DbUpdateConcurrencyException>(StatusCodes.Status409Conflict);
    c.MapToStatusCode<NotImplementedException>(StatusCodes.Status501NotImplemented);
    c.Map<Exception>((context, ex) => {
      var cancelledProblemDetails = ex is OperationCanceledException canceledEx
        ? OperationCancelledExceptionProblemDetails.Create(context, canceledEx)
        : null;
      if (cancelledProblemDetails != null) return cancelledProblemDetails;

      return StatusCodeProblemDetails(ex, StatusCodes.Status500InternalServerError);
    });
    
    // note: we're overriding the default `IsProblem` from the library because YARP is setting the content-length
    // header for a 404 which causes ProblemDetailsMiddleware to NOT return the ProblemDetails response that we want
    c.IsProblem = context => ProblemDetailsOptionsSetup.IsProblemStatusCode(context.Response.StatusCode);
    
    c.AllowedHeaderNames.Add(ApiVsResponseHeaderMiddleware.ApiVersionHeaderName);
  }

  private static StatusCodeProblemDetails StatusCodeProblemDetails<T>(T ex, int statusCode) where T : Exception {
    return new StatusCodeProblemDetails(statusCode) { Detail = ex.GetSafeExceptionMessage() };
  }
}