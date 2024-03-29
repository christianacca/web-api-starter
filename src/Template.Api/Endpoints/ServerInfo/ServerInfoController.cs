using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Extensions.Options;
using Template.Shared.Data;
using Template.Shared.Util;
using ServerInfoModel = Template.Shared.Model.ServerInfo;

namespace Template.Api.Endpoints.ServerInfo {
  [Route("api/[controller]")]
  [ApiController]
  [AllowAnonymous]
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
    public ServerInfoModel Get() {
      return new ServerInfoModel {
        ApiVersion = ApiVersion.Value?.ToString() ?? "", InfraVersion = EnvironmentInfoSettings.InfraVersion
      };
    }
  }
}