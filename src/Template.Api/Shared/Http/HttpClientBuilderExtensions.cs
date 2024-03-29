namespace Template.Api.Shared.Http;

public static class HttpClientBuilderExtensions {
  /// <summary>
  /// Adds a <see cref="EnrichOriginServerExceptionHandler"/> for a named <see cref="HttpClient"/>.
  /// </summary>
  /// <param name="builder">
  /// The <see cref="IHttpClientBuilder" /> instance responsible for configuring this <see cref="HttpClient"/>
  /// </param>
  /// <param name="originServiceName">The friendly name used to identify the upstream origin service</param>
  /// <example>
  /// <code language="c#">
  /// services
  ///   .AddHttpClient&lt;IMyHttpClient, MyHttpClient&gt;()
  ///   .AddEnrichOriginServerExceptionHandler("Orders Service")
  /// </code>
  /// </example>
  public static IHttpClientBuilder AddEnrichOriginServerExceptionHandler(
    this IHttpClientBuilder builder,
    string? originServiceName = null
  ) {
    return builder.AddHttpMessageHandler(_ => new EnrichOriginServerExceptionHandler(originServiceName));
  }
}