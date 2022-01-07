using Microsoft.AspNetCore.Mvc;

namespace Template.Api.Endpoints.OwnEndpoint;

[ApiController]
[Route("api/[controller]")]
[ProducesResponseType(StatusCodes.Status401Unauthorized)]
public class OwnEndpointController : ControllerBase {
  private static readonly string[] Summaries = new[] {
    "Freezing", "Bracing", "Chilly", "Cool", "Mild", "Warm", "Balmy", "Hot", "Sweltering", "Scorching"
  };

  private readonly ILogger<OwnEndpointController> _logger;

  public OwnEndpointController(ILogger<OwnEndpointController> logger) {
    _logger = logger;
  }

  [HttpGet]
  [ProducesResponseType(StatusCodes.Status200OK)]
  public IEnumerable<OwnEndpointModel> Get() {
    return Enumerable.Range(1, 5).Select(index => new OwnEndpointModel {
        Date = DateTime.Now.AddDays(index),
        TemperatureC = Random.Shared.Next(-20, 55),
        Summary = Summaries[Random.Shared.Next(Summaries.Length)]
      })
      .ToArray();
  }
}