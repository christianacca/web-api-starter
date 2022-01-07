using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using Template.Shared.Data;
using ServerInfoModel = Template.Shared.Model.ServerInfo;

namespace Template.Api.Endpoints.ServerInfo {
  [Route("api/[controller]")]
  [ApiController]
  [ProducesResponseType(StatusCodes.Status401Unauthorized)]
  public class ServerInfoController : ControllerBase {
    private AppDatabase Db { get; }

    public ServerInfoController(AppDatabase db) {
      Db = db;
    }

    [HttpGet]
    [ProducesResponseType(StatusCodes.Status200OK)]
    public async Task<ServerInfoModel> Get() {
      return await Db.Set<ServerInfoModel>().FromSqlRaw("SELECT @@VERSION as SqlVersion").FirstAsync();
    }
  }
}