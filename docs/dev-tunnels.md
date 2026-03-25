# Microsoft dev tunnels for local services

Use this guide when you need a public URL for a local service running on your machine.

Default approach for this repo: each developer creates and reuses one persistent dev tunnel, then adds whichever ports they need for the API, App, Functions HTTP endpoints, or the Azurite queue.

Use a shared tunnel only for the cases where preserving one exact public URL across developers matters.

## Port map

Use the table below to decide which local port to expose.

| Local service | Local endpoint | Port | Protocol | Typical use |
| --- | --- | --- | --- | --- |
| API | `https://localhost:5000` | `5000` | `https` | GitHub App webhook callback, browser access, external API callers |
| App | `https://localhost:5001` | `5001` | `https` | Browser access to the local app |
| Functions HTTP | `http://localhost:7071` | `7071` | `http` | Direct access to HTTP-triggered local Azure Functions |
| Azurite queue | `https://127.0.0.1:10001/devstoreaccount1` | `10001` | `https` | Temporary local verification of GitHub Actions queue publication |

For the Functions queue path in this repo, the target queue is `default-queue`.

Before exposing the queue port, make sure Azurite is already running as described in the [Azurite command-line guide](../tools/azurite/README.md#install-and-run-for-command-line).

## URL behavior

If the same persistent tunnel and the same port are hosted again later, the public URL is the same. The URL is tied to the tunnel and port, not to the machine that is currently hosting it.

If a developer creates a different tunnel, that developer gets a different public URL.

If the original tunnel expires and is deleted, recreating it later should be treated as a new tunnel and you should not rely on getting the same public URL back.

> [!INFO]
> The first time you open a dev tunnel URL in a browser with a normal `GET` request, Microsoft may show an anti-phishing interstitial page before forwarding to the local service. This does not block webhook or API clients that call the URL directly.

## Task: create your own persistent tunnel

Objective: create one developer-specific tunnel that you can reuse and add multiple ports to over time.

Choose your own unique tunnel id. Recommended format: `web-api-starter-local-<your-alias>`.

Example using alias `christian`:

```pwsh
devtunnel user login
devtunnel create web-api-starter-local-christian --expiration 30d
devtunnel set web-api-starter-local-christian
```

Add whichever ports you want this tunnel to expose:

```pwsh
devtunnel port create web-api-starter-local-christian -p 5000 --protocol https
devtunnel port create web-api-starter-local-christian -p 5001 --protocol https
devtunnel port create web-api-starter-local-christian -p 7071 --protocol http
devtunnel port create web-api-starter-local-christian -p 10001 --protocol https
```

You only need to add the ports you actually plan to use.

If `devtunnel port create` reports that a port already exists, keep the existing port mapping unless you intentionally want to delete and recreate it.

## Access modes

Choose access per port based on the caller.

Option 1: `anonymous`

Use this when GitHub or another non-interactive caller must reach the exposed port directly.

Examples:

```pwsh
devtunnel access create web-api-starter-local-christian --port 5000 --anonymous
devtunnel access create web-api-starter-local-christian --port 10001 --anonymous
```

Option 2: `tenant`

Use this when you only need interactive access from signed-in users in the current Entra tenant.

Examples:

```pwsh
devtunnel access create web-api-starter-local-christian --port 5001 --tenant
devtunnel access create web-api-starter-local-christian --port 7071 --tenant
```

If you want the same access mode for all ports on the tunnel, you can create the rule at the tunnel level instead of per port.

## Task: host your tunnel

Objective: bring your configured tunnel online after the local services are already running.

Start whichever local services you need first, then host the tunnel:

```pwsh
devtunnel user login
devtunnel host web-api-starter-local-christian
```

This hosts every configured port on that tunnel.

To inspect the configured ports and their public URLs:

```pwsh
devtunnel show web-api-starter-local-christian
devtunnel port list web-api-starter-local-christian
```

## Service-specific usage

### API on port 5000

Use the public URL printed for port `5000` as the API base URL.

For GitHub App webhook delivery, append `/api/github/webhooks`.

For a health check, append `/health`.

### App on port 5001

Use the public URL printed for port `5001` as the App base URL.

For a health check, append `/health`.

### Functions HTTP endpoints on port 7071

Use the public URL printed for port `7071` as the Functions base URL.

For example, append `/api/Echo` to call the local `Echo` function externally.

### Azurite queue on port 10001

Use the public URL printed for port `10001` as the public queue-service relay URL.

For this repo's local Azurite setup, replace the local queue-service base endpoint `https://127.0.0.1:10001/devstoreaccount1` with the tunnel URL plus `/devstoreaccount1`.

For example, if the tunnel prints `https://web-api-starter-local-christian-10001.usw2.devtunnels.ms`, the public queue-service base URL becomes:

```text
https://web-api-starter-local-christian-10001.usw2.devtunnels.ms/devstoreaccount1
```

The workflow queue name remains `default-queue`.

> [!IMPORTANT]
> This queue tunnel is for temporary local verification only. It does not change the steady-state design, which still uses Azure-authenticated queue publication to the real Function App storage account in Azure.
> This tunnel only exposes the local Azurite HTTPS endpoint. Any external publisher still needs Azurite-compatible authentication and must target the tunneled queue endpoint instead of the default local `127.0.0.1` endpoint.

## Task: list your own existing persistent tunnels

Objective: find the tunnels that you already own.

```pwsh
devtunnel user login
devtunnel list
```

This only lists tunnels you own. The CLI does not document tenant-wide discovery of other developers' tunnels.

## Management task: delete one of your persistent tunnels

Objective: permanently remove a tunnel that you own and no longer need.

```pwsh
devtunnel user login
devtunnel delete <your-tunnel-id>
```

Example:

```pwsh
devtunnel delete web-api-starter-local-christian
```

Deleting a tunnel removes that tunnel object. If you later create a new tunnel, do not rely on getting the same public URL back.

For other maintenance tasks not covered here, use the official [Microsoft dev tunnels CLI command reference](https://learn.microsoft.com/en-us/azure/developer/dev-tunnels/cli-commands).

## Advanced task: share one public URL across developers

Objective: let another developer host the same tunnel, preserving the same public URL.

Use this only when multiple developers must reuse one exact public URL.

One developer first creates the shared tunnel. Recommended shared id: `web-api-starter-local-shared`.

The creator must then issue a host token or management token for that shared tunnel. Tenant access on its own is not enough for hosting; tenant access is for connecting.

Creator runs:

```pwsh
devtunnel user login
devtunnel token web-api-starter-local-shared --scopes host
```

Other developer runs:

```pwsh
devtunnel host web-api-starter-local-shared --access-token <host-token>
```

If the other developer also needs to change access rules or ports, issue a management token instead of a host token.

## Task: rotate back to private-by-default after temporary verification

Objective: keep the tunnel reusable for developers, but remove anonymous exposure when it is no longer needed.

Reset access rules, then recreate the tenant-only or anonymous rules you still want:

```pwsh
devtunnel access reset <your-tunnel-id>
```

Then recreate only the access entries you still need, for example:

```pwsh
devtunnel access create <your-tunnel-id> --port 5001 --tenant
devtunnel access create <your-tunnel-id> --port 7071 --tenant
```
