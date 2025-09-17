using Microsoft.Azure.Functions.Worker;
using Microsoft.Azure.Functions.Worker.Middleware;
using Microsoft.Extensions.DependencyInjection;

namespace Template.Functions.Shared.FunctionContextAccessor;

/// <summary>
/// Makes the <see cref="FunctionContext"/> for the current Azure function request available by assignment to
/// <see cref="IFunctionContextAccessor.FunctionContext"/>.
/// </summary>
public class FunctionContextMiddleware : IFunctionsWorkerMiddleware {
  public Task Invoke(FunctionContext context, FunctionExecutionDelegate next) {
    var accessor = context.InstanceServices.GetService<IFunctionContextAccessor>();
    if (accessor != null) {
      accessor.FunctionContext = context;
    }

    return next(context);
  }
}