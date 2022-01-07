using Microsoft.AspNetCore.Mvc.ApplicationModels;

namespace Template.Api.Shared.Mvc;

public class NotFoundResultApiConvention : ApiConventionBase {
  protected override void ApplyControllerConvention(ControllerModel controller) {
    controller.Filters.Add(new NotFoundResultAttribute());
  }
}