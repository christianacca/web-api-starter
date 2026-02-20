using Microsoft.AspNetCore.Mvc;
using System.Text.Json;
using System.Text.Json.Serialization;

namespace Template.Shared.Extensions;

public static class JsonSerializationOptionsExtensions {
  /// <summary>
  /// Configures JsonSerializerOptions with standard settings used across all projects
  /// </summary>
  public static void ConfigureStandardOptions(this JsonSerializerOptions options) {
    options.PropertyNamingPolicy = JsonNamingPolicy.CamelCase;
    options.ReferenceHandler = ReferenceHandler.IgnoreCycles;
    options.Converters.Add(new JsonStringEnumConverter());
  }

  /// <summary>
  /// Configures MVC JSON options with standard settings (convenience overload for use with AddJsonOptions)
  /// </summary>
  public static void ConfigureStandardJsonOptions(this JsonOptions jsonOptions) {
    jsonOptions.JsonSerializerOptions.ConfigureStandardOptions();
  }

  /// <summary>
  /// Removes StringOutputFormatter to force all responses (including plain strings) to be JSON serialized.
  /// Call this when configuring MvcOptions for Function apps.
  /// </summary>
  public static void RemoveStringOutputFormatter(this MvcOptions options) {
    options.OutputFormatters.RemoveType<Microsoft.AspNetCore.Mvc.Formatters.StringOutputFormatter>();
  }
}
