using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Extensions.Options;

namespace Template.Api.Endpoints.Configurations;

[Route("api/[controller]"), ApiController, AllowAnonymous]
public class ConfigurationsController(IOptionsMonitor<ExampleSettings> settings) : ControllerBase {
  [HttpGet]
  [ProducesResponseType(StatusCodes.Status200OK)]
  public ExampleSettings Get() => settings.CurrentValue;
}