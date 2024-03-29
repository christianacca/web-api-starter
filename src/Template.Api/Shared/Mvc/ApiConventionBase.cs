﻿using System.Reflection;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.Mvc.ApplicationModels;

namespace Template.Api.Shared.Mvc;

public abstract class ApiConventionBase : IControllerModelConvention {
  void IControllerModelConvention.Apply(ControllerModel controller) {
    if (IsApiController(controller)) {
      ApplyControllerConvention(controller);
    }
  }

  protected virtual bool IsApiController(ControllerModel controller) {
    if (controller.Attributes.OfType<ApiControllerAttribute>().Any()) {
      return true;
    }

    return controller.ControllerType.Assembly.GetCustomAttributes().OfType<ApiControllerAttribute>().Any();
  }

  protected abstract void ApplyControllerConvention(ControllerModel controller);
}