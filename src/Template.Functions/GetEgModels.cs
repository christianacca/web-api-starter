using Microsoft.AspNetCore.Http;
using Microsoft.Azure.Functions.Worker;
using Microsoft.EntityFrameworkCore;
using Template.Shared.Data;
using Template.Shared.Model;

namespace Template.Functions;

public class GetEgModels {
  private AppDatabase Db { get; }

  public GetEgModels(AppDatabase db) {
    Db = db;
  }

  [Function("EgModels")]
  public async Task<List<ExampleModel>> Run(
    [HttpTrigger(AuthorizationLevel.Anonymous, "get", Route = null)]
    HttpRequest req) {
    return await Db.Examples.ToListAsync();
  }
}