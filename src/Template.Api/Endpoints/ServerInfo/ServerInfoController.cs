using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Options;
using Template.Shared.Data;
using Template.Shared.Util;
using ServerInfoModel = Template.Shared.Model.ServerInfo;

namespace Template.Api.Endpoints.ServerInfo {
  [Route("api/[controller]")]
  [ApiController]
  [ProducesResponseType(StatusCodes.Status401Unauthorized)]
  public class ServerInfoController : ControllerBase {
    private AppDatabase Db { get; }
    
    private EnvironmentInfoSettings EnvironmentInfoSettings { get; }
    
    private Lazy<ProductVersion?> ApiVersion { get; } =
      new(ProductVersion.GetFromAssemblyInformationOf<ServerInfoController>);


    public ServerInfoController(AppDatabase db, IOptionsMonitor<EnvironmentInfoSettings> environmentInfoSettings) {
      Db = db;
      EnvironmentInfoSettings = environmentInfoSettings.CurrentValue;
    }

    [HttpGet]
    [ProducesResponseType(StatusCodes.Status200OK)]
    public async Task<ServerInfoModel> Get(CancellationToken ct) {
      var result = await Db.Set<ServerInfoModel>()
        .FromSqlRaw("SELECT @@VERSION as SqlVersion, '' AS ApiVersion, '' AS InfraVersion").FirstAsync(ct);
      result.ApiVersion = ApiVersion.Value?.ToString() ?? "";
      result.InfraVersion = EnvironmentInfoSettings.InfraVersion;
      return result;
    }
  }
}