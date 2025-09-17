using Microsoft.Azure.Functions.Worker;

namespace Template.Functions.Shared.FunctionContextAccessor;

public interface IFunctionContextAccessor {
  /// <summary>
  /// The current <see cref="FunctionContext"/> for the Azure function request, or null if not available
  /// </summary>
  public FunctionContext? FunctionContext { get; set; }
}