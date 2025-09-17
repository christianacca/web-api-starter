using Microsoft.Azure.Functions.Worker;

namespace Template.Functions.Shared.FunctionContextAccessor;

/// <summary>
/// Manages access to the current <see cref="FunctionContext"/> using an <see cref="AsyncLocal{T}"/>.
/// </summary>
internal sealed class DefaultFunctionContextAccessor : IFunctionContextAccessor {
  private static readonly AsyncLocal<FunctionContextHolder> FunctionContextCurrent = new();

  public FunctionContext? FunctionContext {
    get => FunctionContextCurrent.Value?.Context;
    set {
      var holder = FunctionContextCurrent.Value;
      if (holder != null) {
        // Clear current FunctionContext trapped in the AsyncLocals, as it's done.
        holder.Context = null;
      }

      if (value != null) {
        // Use an object indirection to hold the FunctionContext in the AsyncLocal,
        // so it can be cleared in all ExecutionContexts when it's cleared.
        FunctionContextCurrent.Value = new FunctionContextHolder { Context = value };
      }
    }
  }


  private class FunctionContextHolder {
    public FunctionContext? Context;
  }
}