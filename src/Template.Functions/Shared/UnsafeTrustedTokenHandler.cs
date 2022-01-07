using System.IdentityModel.Tokens.Jwt;
using System.Security.Claims;
using System.Threading.Tasks;
using Microsoft.IdentityModel.Tokens;

namespace Template.Functions.Shared;

/// <summary>
/// Extract a <see cref="ClaimsPrincipal"/> from a JWT token WITHOUT performing validation on that token
/// </summary>
/// <remarks>
/// <para>
///     Usage of this class assumes that the consumer of the functions api is trusted to have already performed that
///     validation
/// </para>
/// <para>
///     At minimum the consumer must be authenticated via a function/api key. Better, to setup Azure Managed Identity
///     between consumer->functions and have the functions app only accessible on a VNet
/// </para>
/// <para>
///     IF we decide that we need to perform double validation of the token (once by YARP and once in the functions app)
///     then use the following article as guidance:
///     https://damienbod.com/2020/09/24/securing-azure-functions-using-azure-ad-jwt-bearer-token-authentication-for-user-access-tokens/
/// </para>
/// </remarks>
public class UnsafeTrustedJwtSecurityTokenHandler : TokenHandler, ISecurityTokenValidator, ITokenValidator {
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
    var claimsPrincipal =
      ((ISecurityTokenValidator)this).ValidateToken(securityToken, TokenValidationParameters, out _);
    return Task.FromResult(claimsPrincipal);
  }

  public bool CanReadToken(string securityToken) {
    return Implementation.CanReadToken(securityToken);
  }

  ClaimsPrincipal ISecurityTokenValidator.ValidateToken(string securityToken,
    TokenValidationParameters validationParameters,
    out SecurityToken validatedToken) {
    var parameters = TokenValidationParameters;
    if (parameters.NameClaimType != validationParameters.NameClaimType) {
      parameters = TokenValidationParameters.Clone();
      parameters.NameClaimType = validationParameters.NameClaimType;
    }

    return Implementation.ValidateToken(securityToken, parameters, out validatedToken);
  }

  bool ISecurityTokenValidator.CanValidateToken => Implementation.CanValidateToken;

  int ISecurityTokenValidator.MaximumTokenSizeInBytes {
    get => ((ISecurityTokenValidator)Implementation).MaximumTokenSizeInBytes;
    set => ((ISecurityTokenValidator)Implementation).MaximumTokenSizeInBytes = value;
  }
}