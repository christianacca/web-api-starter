using System.Security.Claims;
using System.Threading.Tasks;
using Microsoft.AspNetCore.Http;

namespace Template.Functions.Shared;

public interface ITokenValidator {
  Task<ClaimsPrincipal> ValidateTokenAsync(string securityToken);
}

public static class TokenValidatorExtensions {
  public static async Task<ClaimsPrincipal?> ValidateBearerTokenAsync(this ITokenValidator tokenValidator,
    string authorizationHeader) {
    if (string.IsNullOrEmpty(authorizationHeader)) {
      return null;
    }

    if (!authorizationHeader.Contains("Bearer")) {
      return null;
    }

    var accessToken = authorizationHeader.Substring("Bearer ".Length);
    return await tokenValidator.ValidateTokenAsync(accessToken);
  }

  public static Task<ClaimsPrincipal?> ValidateBearerTokenAsync(this ITokenValidator tokenValidator,
    IHeaderDictionary headers) {
    return tokenValidator.ValidateBearerTokenAsync(headers["MRI-Original-Authorization"].ToString());
  }
}