using Microsoft.AspNetCore.Http;
using Microsoft.Azure.Functions.Worker;
using Template.Functions.Shared.FunctionContextAccessor;

namespace Template.Functions.Shared.HttpContextAccessor;

/// <summary>
/// Drop in replacement for <see cref="IHttpContextAccessor"/> that will work for Azure Functions in isolated-process
/// mode.
/// </summary>
/// <remarks>
/// <para>
/// In isolated-process mode, the <see cref="HttpContext"/> is not available via dependency injection. This implementation
/// instead makes the <see cref="HttpContext"/> available via the <see cref="FunctionContext"/>'s
/// <see cref="FunctionContext.Items"/> dictionary.
/// </para>
/// <para>
/// If in the future Microsoft changes the implementation of isolated-process mode to make the <see cref="HttpContext"/>
/// available via <see cref="IHttpContextAccessor"/>, this class will prefer to favour the value of the
/// <see cref="HttpContext"/> supplied via the property setter (ie assigned by Microsoft). At that point, this class
/// will act identically to the default implementation of <see cref="IHttpContextAccessor"/>.
/// </para>
/// </remarks>
/// <param name="functionContextAccessor">
/// The <see cref="IFunctionContextAccessor"/> to use to access the current <see cref="FunctionContext"/>.
/// </param>
public class FunctionHttpContextAccessor(IFunctionContextAccessor functionContextAccessor) : IHttpContextAccessor {
  private static readonly AsyncLocal<ContextHolder> ContextCurrent = new();

  public HttpContext? HttpContext {
    get => ContextCurrent.Value?.Context ?? GetHttpContext(functionContextAccessor.FunctionContext);
    set {
      var holder = ContextCurrent.Value;
      if (holder != null) {
        // Clear current FunctionContext trapped in the AsyncLocals, as it's done.
        holder.Context = null;
      }

      if (value != null) {
        // Use an object indirection to hold the FunctionContext in the AsyncLocal,
        // so it can be cleared in all ExecutionContexts when its cleared.
        ContextCurrent.Value = new ContextHolder { Context = value };
      }
    }
  }


  private static HttpContext? GetHttpContext(FunctionContext? functionContext) {
    if (functionContext == null) return null;
    
    // IMPORTANT: accessing `Items` using `TryGetValue` is NOT thread-safe. However, it's assumed that two threads
    // will not be trying to access the same `FunctionContext` at the same time.
    // This is a reasonable assumption because each `FunctionContext` is scoped to a single function invocation rather
    // than being shared across multiple invocations and therefore potentially multiple threads.

    return functionContext.Items.TryGetValue("HttpRequestContext", out var httpContextObj) &&
           httpContextObj is HttpContext httpContext
      ? httpContext
      : null;
  }

  private class ContextHolder {
    public HttpContext? Context;
  }
}