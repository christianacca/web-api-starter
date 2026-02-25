# TLS Compliance Report

**Purpose:** Justify that this workload satisfies the security requirement to disable TLS 1.0 and TLS 1.1, ensuring only TLS 1.2 and TLS 1.3 are permitted across all accessible endpoints.

**Requirement reference:** BitSight TLS/SSL Configuration Issues — Insecure Protocols Enabled: TLS 1.0 / TLS 1.1  
> *"Disable TLS 1.0 and TLS 1.1 on all web servers, load balancers, application servers, and endpoints. Ensure only secure protocols (TLS 1.2 and TLS 1.3) are enabled."*

---

## Summary

All externally and internally accessible Azure resources in this workload enforce a minimum of TLS 1.2. No resource accepts TLS 1.0 or TLS 1.1 connections. The table below summarises the finding for each resource; detailed evidence follows.

| Resource | Bicep template | Min TLS enforced | How enforced |
|---|---|---|---|
| Public API (Container App) | `api.bicep` | TLS 1.2 / 1.3 | Platform — ACA ingress always uses TLS 1.2 or 1.3 |
| Public App (Container App) | `app.bicep` | TLS 1.2 / 1.3 | Platform — ACA ingress always uses TLS 1.2 or 1.3 |
| Internal API (Azure Functions) | `internal-api.bicep` | TLS 1.3 | Explicit — `siteConfig.minTlsVersion: '1.3'`, `siteConfig.ftpsState: 'FtpsOnly'` |
| Azure SQL Server | `azure-sql-server.bicep` | TLS 1.3 | Explicit — `minimalTlsVersion: '1.3'` |
| Storage Account (PBI reports) | `main.bicep` | TLS 1.2 | AVM module locks `minimumTlsVersion` to `'TLS1_2'` |
| Storage Account (Functions) | `main.bicep` | TLS 1.2 | AVM module locks `minimumTlsVersion` to `'TLS1_2'` |
| App Configuration | `shared-config-store-services.bicep` | TLS 1.2 / 1.3 | Platform — all communication is TLS 1.2 or TLS 1.3 |
| Key Vault | `main.bicep` | TLS 1.2 / 1.3 | Platform — service supports TLS 1.2 and 1.3 only |
| Container Registry (ACR) | `shared-acr-services.bicep` | TLS 1.2+ | Platform — HTTPS-only; TLS negotiated by platform |
| Traffic Manager | `main.bicep` | N/A | DNS-layer only; no TLS termination |

---

## Detailed Evidence

### 1. Azure Container Apps — Public API and App

**Bicep templates:** [`api.bicep`](../tools/infrastructure/arm-templates/api.bicep), [`app.bicep`](../tools/infrastructure/arm-templates/app.bicep)  
**AVM module:** `avm/res/app/container-app:0.20.0`

Both Container Apps set `ingressAllowInsecure: false`, which rejects plain HTTP and requires HTTPS on all inbound traffic.

The Azure Container Apps platform enforces this at the ingress point independently of any application-level configuration. Per official documentation:

> *"[Container Apps] provides HTTPS endpoints that always use TLS 1.2 or 1.3, terminated at the ingress point."*

HTTP requests to port 80 are automatically redirected to HTTPS on port 443.

**Reference:** [Azure Container Apps ingress overview — Microsoft Learn](https://learn.microsoft.com/en-us/azure/container-apps/ingress-overview)

---

### 2. Azure Functions (Internal API)

**Bicep template:** [`internal-api.bicep`](../tools/infrastructure/arm-templates/internal-api.bicep)  
**AVM module:** `avm/res/web/site:0.21.0`

The `siteConfig` block explicitly sets:

```bicep
siteConfig: {
  netFrameworkVersion: 'v10.0'
  use32BitWorkerProcess: false
  cors: { ... }
  http20Enabled: true
  minTlsVersion: '1.3'
  ftpsState: 'FtpsOnly'
}
```

Per official documentation, `minTlsVersion: '1.3'` causes App Service (and therefore Azure Functions, which runs on the same platform) to reject any inbound connection that negotiates a TLS version lower than 1.3. Only TLS 1.3 connections are accepted.

`ftpsState: 'FtpsOnly'` ensures that plain FTP is rejected; only FTPS (FTP over TLS) is permitted for any deployment tooling that uses the FTP endpoint.

Both settings are declared explicitly in the Bicep template, making this configuration independent of any future platform default changes.

**Reference:** [What is TLS/SSL in Azure App Service? — Microsoft Learn](https://learn.microsoft.com/en-us/azure/app-service/overview-tls)

---

### 3. Azure SQL Server

**Bicep template:** [`azure-sql-server.bicep`](../tools/infrastructure/arm-templates/azure-sql-server.bicep)  
**AVM module:** `avm/res/sql/server:0.21.1`

The Bicep template explicitly sets `minimalTlsVersion: '1.3'` on both the primary and failover SQL servers, causing Azure SQL Database to reject any client connection that negotiates a TLS version lower than 1.3.

Additionally, Microsoft has retired TLS 1.0 and TLS 1.1 support from Azure SQL Database at the platform level:

> *"TLS 1.0 and 1.1 are retired and no longer available."*

> *"Starting November 2024, you'll no longer be able to set the minimal TLS version for Azure SQL Database and Azure SQL Managed Instance client connections below TLS 1.2."*

> *"Setting a minimum TLS version ensures a baseline level of compliance and guarantees support for newer TLS protocols. For example, choosing TLS 1.2 means only connections with TLS 1.2 or TLS 1.3 are accepted, while connections using TLS 1.1 or lower are rejected."*

**Reference:** [Connectivity settings for Azure SQL Database — Microsoft Learn](https://learn.microsoft.com/en-us/azure/azure-sql/database/connectivity-settings)

---

### 4. Azure Storage Accounts

**Bicep template:** [`main.bicep`](../tools/infrastructure/arm-templates/main.bicep) (two accounts: PBI reports storage and Functions storage)  
**AVM module:** `avm/res/storage/storage-account:0.31.0`

The AVM `storage-account` module enforces `minimumTlsVersion: 'TLS1_2'` as its only permitted value. This is a constraint built into the module — callers cannot set a lower value. Per official documentation:

> *"Azure Storage accounts permit clients to send and receive data with TLS versions 1.2 and above. When a storage account requires a minimum TLS version, any request that uses an older version will fail."*

> *"When the `MinimumTlsVersion` property is not set... the storage account will permit requests sent with TLS version 1.0 or greater."*

Because the AVM module explicitly sets `minimumTlsVersion` to `'TLS1_2'`, the accounts are compliant regardless of platform defaults.

**Reference:** [Enforce a minimum required version of TLS for requests to a storage account — Microsoft Learn](https://learn.microsoft.com/en-us/azure/storage/common/transport-layer-security-configure-minimum-version)

---

### 5. Azure App Configuration

**Bicep template:** [`shared-config-store-services.bicep`](../tools/infrastructure/arm-templates/shared-config-store-services.bicep)  
**AVM module:** `avm/res/app-configuration/configuration-store:0.9.2`

App Configuration's TLS policy is enforced at the platform level and is not configurable by the customer. Per official documentation:

> *"App Configuration always encrypts all data in transit and at rest. All network communication is over TLS 1.2 or TLS 1.3."*

No Bicep configuration is required or possible to enforce this; it is a service guarantee.

**Reference:** [Azure App Configuration FAQ — Microsoft Learn](https://learn.microsoft.com/en-us/azure/azure-app-configuration/faq)

---

### 6. Azure Key Vault

**Bicep template:** [`main.bicep`](../tools/infrastructure/arm-templates/main.bicep) (and [`shared-keyvault-services.bicep`](../tools/infrastructure/arm-templates/shared-keyvault-services.bicep))  
**AVM module:** `avm/res/key-vault/vault:0.13.3`

Key Vault's TLS policy is enforced at the platform level and is not configurable by the customer. Per official documentation:

> *"Azure Key Vault supports TLS 1.2 and 1.3 protocol versions to ensure secure communication between clients and the service."*

No Bicep configuration is required or possible to enforce this; it is a service guarantee.

**Reference:** [Secure your Azure Key Vault — Microsoft Learn](https://learn.microsoft.com/en-us/azure/key-vault/general/security-features)

---

### 7. Azure Container Registry (ACR)

**Bicep template:** [`shared-acr-services.bicep`](../tools/infrastructure/arm-templates/shared-acr-services.bicep)  
**AVM module:** `avm/res/container-registry/registry:0.10.0`

ACR exposes all registry operations exclusively over HTTPS. There is no option to configure or permit unencrypted HTTP access, and no customer-configurable minimum TLS version setting exists. TLS version negotiation is managed by the Azure platform.

ACR is a management-plane resource used during deployment (image push/pull by CI/CD pipelines and ACA). It is not a runtime endpoint accessible to end users.

**Reference:** [Azure Container Registry overview — Microsoft Learn](https://learn.microsoft.com/en-us/azure/container-registry/container-registry-intro)

---

### 8. Traffic Manager

**Bicep template:** [`traffic-manager-profile.bicep`](../tools/infrastructure/arm-templates/traffic-manager-profile.bicep) (via `main.bicep`)

Traffic Manager operates at the DNS layer only. It does not terminate TCP or TLS connections. Client TLS connections are established directly with the origin endpoints (the Container Apps and Azure Functions), where TLS 1.2+ is enforced as described above.

Traffic Manager itself presents no HTTP/HTTPS endpoint and therefore has no TLS version to configure.

---

## Conclusion

Every endpoint and service accessible within this workload enforces TLS 1.2 as the minimum protocol version, either through:

- **Explicit Bicep configuration** (Internal API / Azure Functions — `minTlsVersion: '1.3'`, `ftpsState: 'FtpsOnly'`; Azure SQL Server — `minimalTlsVersion: '1.3'`)
- **AVM module defaults** (Storage Accounts — `minimumTlsVersion: 'TLS1_2'`)
- **Platform-level service guarantees** (Azure Container Apps, App Configuration, Key Vault)

TLS 1.0 and TLS 1.1 are not accepted by any resource in this workload. The workload satisfies the stated security requirement.
