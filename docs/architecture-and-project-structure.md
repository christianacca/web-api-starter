# Architecture and Project structure

## Architecture

* ASP.NET (aka core) API
    * MS Application Insights configured to suitable conventions
    * [ProblemDetails middleware](https://www.nuget.org/packages/Hellang.Middleware.ProblemDetails/) to format non-success responses
    * [YARP middleware](https://microsoft.github.io/reverse-proxy/index.html) to proxy requests to other APIs that you want to aggregate with your API
      (typical for a "backend for frontend" architecture)
* Azure Functions app for:
    * API endpoints that you prefer to implement using serverless model
    * Asynchronous work you want to offload from the ASP.NET API above
* Azure managed identity to avoid API keys, OAuth client secrets and database passwords
* Azure AD authentication for Azure SQL database
* Entity Framework Core (providing examples of a typical setup and configuration)
* Automation scripts for implementing Infrastructure as Code (IaC)
* Convenient dev scripts for deploying the app to Azure from your dev machine
* CI/CD pipelines for both infrastructure and app deployment

## Project structure

* Azure.ManagedIdentity: utility library for acquiring managed identity access tokens
* Template.Api: API endpoints
* Template.Functions:
  * API endpoints that are more convenient to write as functions (for example to use input/output bindings to other azure services)
  * Background jobs/queues or long running async workflows (using durable functions)
* Template.Shared:
  * Code that needs to be shared across Template.Api and Template.Functions projects