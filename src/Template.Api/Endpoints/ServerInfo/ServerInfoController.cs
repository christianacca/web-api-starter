using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using Template.Shared.Data;
using Template.Shared.Util;
using ServerInfoModel = Template.Shared.Model.ServerInfo;

namespace Template.Api.Endpoints.ServerInfo {
  [Route("api/[controller]")]
  [ApiController]
  [ProducesResponseType(StatusCodes.Status401Unauthorized)]
  public class ServerInfoController : ControllerBase {
    private AppDatabase Db { get; }
    
    private Lazy<ProductVersion?> ApiVersion { get; } =
      new(ProductVersion.GetFromAssemblyInformationOf<ServerInfoController>);


    public ServerInfoController(AppDatabase db) {
      Db = db;
    }

    [HttpGet]
    [ProducesResponseType(StatusCodes.Status200OK)]
    public async Task<ServerInfoModel> Get(CancellationToken ct) {
      var result = await Db.Set<ServerInfoModel>().FromSqlRaw("SELECT @@VERSION as SqlVersion, '' AS ApiVersion").FirstAsync(ct);
      result.ApiVersion = ApiVersion.Value?.ToString() ?? "";
      return result;
    }
  }
}