using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;
using System.Diagnostics.CodeAnalysis;
using System.Text.Json;

namespace Template.Functions.Shared;

public readonly record struct ReadJsonResult<T>(T? Value, IActionResult? Error) where T : class {

  /// <summary>
  /// Indicates whether the request body was successfully read and deserialized.
  /// </summary>
  [MemberNotNullWhen(true, nameof(Value))]
  [MemberNotNullWhen(false, nameof(Error))]
  public bool IsSuccess => Error is null;
}

public static class HttpRequestExtensions {
  /// <summary>
  /// Reads JSON from the request body and returns either the deserialized value or an error result.
  /// </summary>
  /// <typeparam name="T">The type to deserialize to</typeparam>
  /// <returns>A result that contains either the deserialized value or an error.</returns>
  /// <example>
  /// <code language="c#">
  /// var result = await req.TryReadFromJsonAsync&lt;MyDto&gt;(cancellationToken);
  /// if (!result.IsSuccess) return result.Error;
  /// var dto = result.Value;
  /// </code>
  /// </example>
  public static async Task<ReadJsonResult<T>> TryReadFromJsonAsync<T>(
    this HttpRequest req,
    CancellationToken ct = default
  ) where T : class {
    T? value;
    try {
      value = await req.ReadFromJsonAsync<T>(ct);
    }
    catch (InvalidOperationException ex) when (ex.Message.StartsWith("Unable to read the request as JSON", StringComparison.OrdinalIgnoreCase)) {
      return new ReadJsonResult<T>(null,
        new BadRequestObjectResult(
          $"Unable to read the request as JSON because the request content type '{req.ContentType}' is not a known JSON content type."
        )
      );
    }
    catch (JsonException) {
      return new ReadJsonResult<T>(null, new BadRequestObjectResult("Invalid request body format"));
    }

    if (value == null) {
      return new ReadJsonResult<T>(null, new BadRequestObjectResult("Request body cannot be null"));
    }

    return new ReadJsonResult<T>(value, null);
  }
}
