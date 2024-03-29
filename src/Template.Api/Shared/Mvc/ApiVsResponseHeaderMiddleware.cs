using System.Reflection;
using Template.Shared.Util;

namespace Template.Api.Shared.Mvc;

public class ApiVsResponseHeaderMiddleware {
  public const string ApiVersionHeaderName = "X-Mri-Api-Version";

  private Lazy<ProductVersion?> ApiVersion { get; } = 
    new(() => ProductVersion.GetFromAssemblyInformation(Assembly.GetExecutingAssembly()));

  private RequestDelegate Next { get; }

  public ApiVsResponseHeaderMiddleware(RequestDelegate next) {
    Next = next;
  }

  public async Task Invoke(HttpContext context) {
    if (ApiVersion.Value != null) {
      context.Response.Headers[ApiVersionHeaderName] = ApiVersion.ToString();  
    }
    await Next(context);
  }
}