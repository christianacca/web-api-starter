using System.Collections.Generic;
using System.Threading.Tasks;
using Microsoft.AspNetCore.Http;
using Microsoft.Azure.WebJobs;
using Microsoft.Azure.WebJobs.Extensions.Http;
using Microsoft.EntityFrameworkCore;
using Template.Shared.Data;
using Template.Shared.Model;

namespace Template.Functions;

public class GetEgModels {
  private AppDatabase Db { get; }

  public GetEgModels(AppDatabase db) {
    Db = db;
  }

  [FunctionName("EgModels")]
  public async Task<List<ExampleModel>> Run(
    [HttpTrigger(AuthorizationLevel.Anonymous, "get", Route = null)]
    HttpRequest req) {
    return await Db.Examples.ToListAsync();
  }
}