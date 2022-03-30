# Starter project for an API project

## Overview

Clone this repo and copy the solution to kickstart the effort of creating a new API

## Architecture and Project structure

See [architecture-and-project-structure.md](docs/architecture-and-project-structure.md)

## Connecting to Azure from local machine

1. Establish an authenticated session with Azure with any of the following tools:
   * Visual Studio
   * Visual Studio Code
   * Azure CLI (`az login`)
   * Powershell (`Connect-AzAccount`)
2. Modify appsettings as detailed below either by using dotnet user-secrets (preferred) or directly in appsettings.Development.json file.

### appsettings

* API + Function app -> Azure SQL: 
  * `ConnectionStrings__AppDatabase`: `Server=<your_sql_server>.database.windows.net; Database=<your_db_name>; Authentication=Active Directory Default;`
* API -> Azure function app:
  * `Api__FunctionsAppToken__Audience`: set this to the value of the App/Client ID of the Azure AD App registration associated with the function app
  * `Api__ReverseProxy__Clusters__FunctionsApp__Destinations__Primary__Address`: set this to the public url of the Azure function app

**IMPORTANT**: 
currently there is a problem connecting the API running on a dev machine to Azure functions. 
A support ticket with Microsoft has been opened to resolve this

See [deploy-app.md](docs/deploy-app)