using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Azure.Functions.Worker;
using Microsoft.EntityFrameworkCore;
using Template.Shared.Data;

namespace Template.Functions;

public class GetEgModels {
  private AppDatabase Db { get; }

  public GetEgModels(AppDatabase db) {
    Db = db;
  }

  [Function("EgModels")]
  public async Task<IActionResult> Run(
    [HttpTrigger(AuthorizationLevel.Anonymous, "get", Route = null)]
    HttpRequest req) {
    var result = await Db.Examples.ToListAsync();
    return new OkObjectResult(result);
  }
}