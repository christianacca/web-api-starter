using Hellang.Middleware.ProblemDetails;
using Microsoft.AspNetCore.Mvc;
using Mri.AppInsights.AspNetCore;
using Template.Api.Shared.Http;

namespace Template.Api.Shared.ExceptionHandling;

public static class OperationCancelledExceptionProblemDetails {
  public static ProblemDetails? Create(HttpContext context, OperationCanceledException ex) {
    // map exceptions thrown to trigger code to abort due to the caller aborting (aka cancel) their request?
    if (context.RequestAborted.IsCancellationRequested && ExceptionPredicate.IsCancellation(ex)) {
      return new StatusCodeProblemDetails(499) { Title = "Operation cancelled by caller" };
    }

    // map exception thrown due to a HttpClient request timeout
    if (ex.IsHttpClientTimeout()) {
      var originInfo = ex.GetOriginInfo();
      var originServiceName = originInfo?.OriginServiceName ?? "upstream service";
      return new StatusCodeProblemDetails(StatusCodes.Status504GatewayTimeout) {
        Detail = $"The request to {originServiceName} was taking too long and has timed out",
        Extensions = { { "originRequestUri", originInfo?.OriginRequestUri } }
      };
    }

    // let someone else attempt to map this exception
    return null;
  }

  private static bool IsHttpClientTimeout(this Exception ex) {
    // see: https://devblogs.microsoft.com/dotnet/net-5-new-networking-improvements/
    return ex is TaskCanceledException && ex.InnerException is TimeoutException;
  }
}