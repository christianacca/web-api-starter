using Microsoft.AspNetCore.Builder;
using Microsoft.AspNetCore.Hosting;

namespace Template.Functions.Shared;

/// <summary>
/// Injects <c>UseAuthentication()</c> into the ASP.NET Core pipeline before the Functions middleware runs.
/// </summary>
/// <remarks>
/// <para>
///   <c>ConfigureFunctionsWebApplication()</c> builds an ASP.NET Core pipeline but does not wire up
///   <c>UseAuthentication()</c>. Without it, <see cref="Microsoft.AspNetCore.Http.HttpContext.User"/> is always
///   unauthenticated in isolated-process mode, even when a valid bearer token is present and EasyAuth has already
///   accepted it at the platform level.
/// </para>
/// <para>
///   <see cref="IStartupFilter"/> is processed by the ASP.NET Core web host before the <c>Configure</c> callback,
///   so <c>UseAuthentication()</c> correctly precedes <c>UseRouting()</c> / <c>UseEndpoints()</c> in the pipeline.
/// </para>
/// <para>
///   <b>Future migration</b>: the Functions team has a tracked TODO in <c>FunctionsHostBuilderExtensions.ConfigureAspNetCoreIntegration</c>
///   to expose a first-class hook for customers to configure the ASP.NET Core middleware pipeline. Once that ships,
///   replace this <see cref="IStartupFilter"/> with a direct <c>app.UseAuthentication()</c> call in that hook and
///   remove the <c>AddTransient&lt;IStartupFilter, UseAuthenticationStartupFilter&gt;()</c> registration from
///   <c>Program.cs</c>.
/// </para>
/// </remarks>
internal class UseAuthenticationStartupFilter : IStartupFilter {
  public Action<IApplicationBuilder> Configure(Action<IApplicationBuilder> next) {
    return app => {
      app.UseAuthentication();
      next(app);
    };
  }
}