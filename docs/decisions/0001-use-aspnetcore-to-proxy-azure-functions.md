# Use ASP.NET Core YARP middleware to reverse proxy Azure functions

* Status: accepted
* Deciders: Christian Crowhurst, Moshe Gottlieb, Sowmya Suresh

Technical Story: [EDS-BI: DSG Backend API - Proof-of-concept](https://mripride.atlassian.net/browse/EDP-66)

## Context and Problem Statement

Do we use Azure functions as a backend API for the frontend SPA, or do we continue to use ASP.NET (core) API?

## Decision Drivers

Why consider azure functions?

* identify potential cost savings, either from reduced runtime or development costs
* identify new architectural patterns that are optimized for the cloud

## Considered Options

* [Azure Functions as API](https://azure.microsoft.com/en-gb/services/functions/)
* [ASP.NET Core API](https://docs.microsoft.com/en-us/aspnet/core/?view=aspnetcore-6.0)
* Azure Function as API + [Azure APIM](https://azure.microsoft.com/en-gb/services/api-management/)
    * ie use Azure API Management to act as a reverse proxy in front of Azure functions
* ASP.NET Core API + Azure Function (ASP.NET Core API proxying Azure functions)
* Azure Static Web Apps

## Decision Outcome

Chosen option: ASP.NET Core API + Azure Function (ASP.NET Core API proxying Azure functions), because it provides the sweet spot for taking advantage of:

* the low-code architecture of Azure functions 
* using ASP.NET Core API for it's rich middleware and model binding pipeline
* without the additional friction APIM when all you want to do to perform JWT validation for Azure function calls

**Note**: If welcome frontend was a fully compliant OIDC provider, the choice would likely change to using Azure Static Web Apps

With the chosen strategy, implementing any given endpoint in that API is a choice between:

1. implement "all" the logic in the API controller (contrast to azure functions app demo)
2. proxy the request to Azure functions app (using YARP middleware) ie use API for JWT validation (etc) and let function app perform request
3. treat the controller as a message broker of sorts (eg: api writes image to blob storage and immediately returns)

Where the asp.net controller is acting as a message broker, code in the controller simply writes a "message" to some form of queue / table / blob or publishes an event (as in pub-sub). 
Then have another azure functions app be triggered as a new "message" or event arrives. For that function to process or be part of a series of functions in that functions app that orchestrate the work for that message. 
In other words let functions act as worker processes and let asp.net core api "feed" the queue for those workers.


## Pros and Cons of the Options

### Azure Functions as API

#### Pros

* Potential cost of sales reduction - pay per request rather than idle time
* Scaling from zero to "infinite" with scaling criteria specific to each type of function trigger
* Simplifies triggering custom logic/workflows/orchestrations on a schedule or when events happen in various azure services (eg when a message arrives in a queue, an item is inserted into a cosomos db container, etc). EG
    * implementing glue code _between_ azure services
    * job queue implementation
    * timer based job scheduling
* Input and output bindings minimize boilerplate code for interacting with other azure services (eg storage, queues, database)
* no-code integration with application insights
* ability to share subset of business logic / model code with front-end (caveat: might be fiddly to setup in practice)

#### Cons

* Lack of prior experience to know what rough edges WILL be encountered in any tech (we don't know what we don't know)
* No standards based JWT authentication
    * The recommendation is to use APIM as a reverse proxy to offload JWT validation (see section below on further pros/cons)
* No flexible authorization system
* Input and output bindings could lead to anti-patterns. EG:
    * embedding large amounts of sql as string literals into function attributes of functions.json file
* No concept of a rich middleware pipeline to implement cross cutting concerns. Canonical examples:
    - exception formatting and logging via ProblemDetails middleware
    - dropping in an off-the-shelf middleware for handling specific/group of requests (eg service health, SCIM, YARP)
    - request enrichment (eg adding ClientID to all requests headers)
* Limited model binding
    - functions: model binding to a posted JSON body only
    - asp.net core: as functions plus automatic model validation and/or bind to multiple source of data such as html form fields, route path data, query parameters, request header or custom data sources
* Reduce flexibility to globally customize application insight telemetry (eg adding client id to all request telemetry)

In summary: ASP.NET (core) API is a full featured stack, Azure functions is not but offers compelling low code solutions

### ASP.NET Core API

#### Pros

See the cons of using Azure Functions as API

#### Cons

* Potentially more code to write to solve the same problem due to lack of rich Input/Output bindings in Azure Functions
    * Note: this could be mitigated by using [DAPR](https://docs.dapr.io/developing-applications/building-blocks/bindings/)
* More work to implement async patterns compared to Azure functions

### Azure Function as API + [Azure APIM]

#### Pros

* Offload JWT validation
* Easily add built-in policies such as rate limiting
* Knobs and dials to add api versioning strategies
* Ability to aggregate other api's that the SPA code might need to consume

#### Cons

Adds a lot of friction for an API that could be instead accessed directly.

* APIM policies need to be kept in synch with changes to the functions app as we add/modify/remove functions
* Source control seems clunky involving hand rolled and/or community solutions
* Increases devops complexity due to APIM being a shared resource and not having a easy deployment story (hand rolled/community solutions)
* Harder to do local dev in a way that is production like

### ASP.NET Core API + Azure Function

#### Pros

All the advantages of Azure Functions along with all the advantages of ASP.NET Core API

#### Cons

We lose rich APIM policies (although some of these policies can be applied via open source ASP.NET middleware)

### Azure Static Web Apps

#### Pros

* serve static assets over Azure CDN
* Azure functions app as backend
* Zero code authentication
* Ready-rolled devops pipeline for deploying SPA and Functions app
* Separate SPA and functions published app environment for every PR!
* Very generous free tier

#### Cons

* Currently no support for triggers other than HTTP. The implication is that we might need to deploy another Azure functions app in addition to the Functions App as API
* Authentication cannot use Welcome Frontend proxy (welcome is not a compliant OIDC provider)

## Links <!-- optional -->

* Hand rolled JWT validation in Azure Functions: https://damienbod.com/2020/09/24/securing-azure-functions-using-azure-ad-jwt-bearer-token-authentication-for-user-access-tokens/
    * see second to last paragraph at bottom of post: "If implementing only APIs, ASP.NET Core Web API projects would be a better solution where standard authorization flows, standard libraries and better tooling are per default."
* YARP announcement: https://devblogs.microsoft.com/dotnet/announcing-yarp-1-0-release/
* YARP GitHub demo of JWT validation offload: https://damienbod.com/2021/01/11/protecting-legacy-apis-with-an-asp-net-core-yarp-reverse-proxy-and-azure-ad-oauth/
* APIM performing JWT validation: https://medium.com/microsoftazure/secure-functions-apim-identityserver4-4b6f62d773b0
* Azure Static Web App: https://azure.microsoft.com/en-us/services/app-service/static/#documentation
* Create a function app that connects to Azure services using identities instead of secrets: https://docs.microsoft.com/en-us/azure/azure-functions/functions-identity-based-connections-tutorial
* Use identity-based connections instead of secrets with triggers and bindings: https://docs.microsoft.com/en-us/azure/azure-functions/functions-identity-based-connections-tutorial-2
