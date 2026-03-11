using System.IdentityModel.Tokens.Jwt;
using System.Security.Claims;
using Microsoft.IdentityModel.Tokens;

namespace Template.Functions.Shared;

/// <summary>
/// Constructs a <see cref="ClaimsPrincipal"/> from a JWT token by deserializing its claims, without re-validating
/// the token's signature, issuer, audience, or lifetime.
/// </summary>
/// <remarks>
/// <para>
///   Token validation is deliberately skipped because it has already been performed upstream, in one of two ways:
/// </para>
/// <list type="bullet">
///   <item>
///     <description>
///       <b>EasyAuth (platform level)</b>: Azure Functions EasyAuth validates the bearer token before the request
///       reaches the worker process. The token in the <c>Authorization</c> header can be trusted.
///     </description>
///   </item>
///   <item>
///     <description>
///       <b>YARP reverse proxy</b>: The API gateway validates the user's token and forwards it to the function app
///       via the <c>MRI-Original-Authorization</c> header. The token is an access token originally issued for the
///       API, not the function app — so re-validating audience/issuer would correctly fail. EasyAuth must still be
///       configured on the function app to ensure only trusted callers (e.g. the API's managed identity) can reach it.
///     </description>
///   </item>
/// </list>
/// </remarks>
public class UnsafeTrustedJwtSecurityTokenHandler : TokenHandler, ITokenValidator {
  private JwtSecurityTokenHandler Implementation { get; }
  protected TokenValidationParameters TokenValidationParameters { get; }

  private static JwtSecurityTokenHandler CreateDefaultImplementation() {
    return new JwtSecurityTokenHandler { MapInboundClaims = false };
  }

  public UnsafeTrustedJwtSecurityTokenHandler() : this(CreateDefaultImplementation()) {
  }

  public UnsafeTrustedJwtSecurityTokenHandler(JwtSecurityTokenHandler? implementation) {
    implementation ??= CreateDefaultImplementation();
    var noValidationParameters = new TokenValidationParameters {
      RequireSignedTokens = false,
      RequireAudience = false,
      RequireExpirationTime = false,
      TryAllIssuerSigningKeys = false,
      ValidateActor = false,
      ValidateAudience = false,
      ValidateIssuer = false,
      ValidateIssuerSigningKey = false,
      ValidateLifetime = false,
      ValidateTokenReplay = false,
      SignatureValidator = (token, _) => implementation.ReadToken(token)
    };
    if (!implementation.MapInboundClaims) {
      noValidationParameters.NameClaimType = JwtRegisteredClaimNames.Sub;
    }

    Implementation = implementation;
    TokenValidationParameters = noValidationParameters;
  }

  public Task<ClaimsPrincipal> ValidateTokenAsync(string securityToken) {
    var claimsPrincipal = ValidateTokenCore(securityToken, TokenValidationParameters, out _);
    return Task.FromResult(claimsPrincipal);
  }

  public override Task<TokenValidationResult> ValidateTokenAsync(string token,
    TokenValidationParameters validationParameters) {
    try {
      var claimsPrincipal = ValidateTokenCore(token, validationParameters, out var securityToken);
      return Task.FromResult(new TokenValidationResult {
        IsValid = true,
        ClaimsIdentity = claimsPrincipal.Identity as ClaimsIdentity,
        SecurityToken = securityToken
      });
    } catch (Exception ex) {
      return Task.FromResult(new TokenValidationResult { IsValid = false, Exception = ex });
    }
  }

  private ClaimsPrincipal ValidateTokenCore(string securityToken,
    TokenValidationParameters validationParameters,
    out SecurityToken validatedToken) {
    var parameters = TokenValidationParameters;
    if (parameters.NameClaimType != validationParameters.NameClaimType) {
      parameters = TokenValidationParameters.Clone();
      parameters.NameClaimType = validationParameters.NameClaimType;
    }

    return Implementation.ValidateToken(securityToken, parameters, out validatedToken);
  }
}