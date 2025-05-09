<!-- TOC -->
* [Overview](#overview)
  * [Store used for an environment](#store-used-for-an-environment)
  * [Labelling keys and feature flags](#labelling-keys-and-feature-flags)
  * [Label priority](#label-priority)
  * [Adding, deleting, or modifying feature flags](#adding-deleting-or-modifying-feature-flags)
  * [Adding, deleting, or modifying configuration keys](#adding-deleting-or-modifying-configuration-keys)
<!-- TOC -->

# Overview

The solution uses [Azure App Configuration](https://azure.microsoft.com/en-us/products/app-configuration) to manage configuration values and 
feature status (typically enabled/disabled) and feature value variations.

Configuration is referred to as keys, whereas feature status is referred to as feature flags. For configuration values, 
there are multiple sources that are used to load the final set of values, into a workload service such as the api.
Configuration defined in the Azure app configuration store are typically those keys that need to change without requiring
a deployment ie are more dynamic in nature. Feature status is typically only defined in the Azure app configuration store.

Feature flags typically are used to decouple when a feature is deployed to when a feature is release ie made available.
In that sense they are a temporary in nature. Once the feature has been made available in all environment, they will be
then be removed.

That said, it is possible that feature management can be used as a permanent mechanism when certain features / capabilities
need to be enabled/disabled per client say, and you want to use the feature management UI in the azure portal to manage
which client that feature is available to.

## Store used for an environment

Azure app configuration store is a service shared by multiple workload environments. Typically, there is a separate store
that serves prod and staging environments, and a dev/test store that serves all other environments, including demo.

To find which store is used for each environment run the following script:

```pwsh
./tools/infrastructure/print-product-convention-table.ps1 { $_.ConfigStores.Current } -AsArray | Select Env, ResourceName, ResourceGroupName
```

## Labelling keys and feature flags

Keys and feature flags are loaded from the store based on a priority of labels assigned to the keys and flags. The labels
assigned is based on the name of the environment for which that key or flag is required. So for example, a key assigned
the label "prod-na" will be loaded by the workload services (api, etc) running in the prod-na environment.

A key or flag may also have no label in which case that key will be loaded by all the workload services being served by
that store, regardless of the environment the workload service is running within.

Finally, a label can be assigned to a key or flag to denote a set of environments that all share the same prefix. So for
example, the label "demo" can be assigned to a key or flag, and that key or flag will be loaded by workload services that
are running in any environment whose name starts with "demo", eg demo-apac, demo-na, etc.

## Label priority

The same key or feature flag can have more than one value, where each value is associated with a label. So for example
the feature flag "AskAgora" can have a value of `true` without a label, and a value of `false` with the label "staging".

For keys or flags that have multiple values, differentiated by label, a label priority will determine the final value for
that key or flag. The order of label priority, from least to hightest:

* no label
* environment prefix eg "demo", or "prod"
* environment eg "dev", "qa", "demo-apac", "prod-na"

For our "AskAgora" feature flag example:

* `true` (no label)
* `false` ("staging")

When that flag is loaded in the staging environment, it will have a value of `false`. For all other environments where
the flag is loaded from that same store, the value will be `true`.

## Adding, deleting, or modifying feature flags

> [!IMPORTANT]
> Modifications to feature flags will be reflected in the workload service that consumes the store after the given elapsed
> interval set by the workload services (the default is 30 seconds). However, where that flag is consumed by another
> app like an angular SPA, the change will likely not be reflected until the app is reloaded ie the page fully reloaded.
> For changes to be made available sooner in such apps like SPA, would require the SPA and it's backend api to implement
> some mechanism to poll or be notified of changes to the feature flag.

> [!NOTE]
> For general guidance see:
> * [Enable conditional features with feature filters](https://learn.microsoft.com/en-us/azure/azure-app-configuration/howto-feature-filters)
> * [.NET Feature Management](https://learn.microsoft.com/en-us/azure/azure-app-configuration/feature-management-dotnet-reference)

First thing to consider is: have in mind which environment requires the feature flag **enabled**.

A feature flag that is not defined is off by default. So for example, if the feature is not to be enabled in production yet,
you can skip addding a feature flag for the store serving the production environments. However, if there is an anticipation
that the feature is going to be enabled without requiring a deployment then it's good idea to create the feature flag ahead
of time, but disabled. That way the flag can be enabled using the feature toggle button in the Azure portal.

Next to consider is what environments do you want the flag to be enabled for. As per the above sections:

* there can be a separate store for prod+staging, and another for all other environments
* labels can be assigned to target specific environments served by that store

Once you have identified the correct store, you will need to ensure you have permissions to manage the flags in that store.
You will need Azure RBAC role [App Configuration Contributor](https://learn.microsoft.com/en-us/azure/azure-app-configuration/concept-enable-rbac#control-plane-access) for that store. Typically, this permission is granted
as part of assigning Azure permissions as explained in the section [Granting access to Azure or Power-BI resources](deploy-app.md#granting-access-to-azure-or-power-bi-resources).
The access level required:

* prod and staging environments: "App Admin / support-tier-2"
* dev/test including demo: "development" or "App Admin / support-tier-2"

Now that you've identified the config store and the label(s) to assign to the feature flag:

1. Browse to the "Operations" > "Feature manager" blade on the Azure app config service in the Azure portal
2. Select "+Create" > "Feature flag" menu item and supply the following:
   * "Enable feature flag": check this option for the feature to be enabled, or unchecked for the feature to be disabled
   * "Feature flag name": the exact name used as the feature in code for the workload service implementing that feature
   * "Label": the label that identifies the environment(s) the flag should apply. Remember, that no label will cause the
     flag to apply to all environments served by that store
   * "Description": (optional) a short description of the feature flag
3. As required add a labelled value to the Feature flag - select "..." > "+Create label" menu item and supply the following:
   * "Enable feature flag": check this option for the feature to be enabled, or unchecked for the feature to be disabled
   * "Label": the label that identifies the environment(s) the flag should apply

To remove a feature flag:

1. Browse to the "Operations" > "Feature manager" blade on the Azure app config service in the Azure portal
2. Select each value for the feature flag (you might have created multiple labelled value) from the list of feature flags
3. Select the "Delete" button on the top menu bar

## Adding, deleting, or modifying configuration keys

> [!IMPORTANT]
> Modifications to configuration keys will be reflected in the workload service that consumes the store after the given elapsed
> interval set by the workload services (the default is 30 seconds). But ONLY when the sentinel key value for that environment
> has also been modified. So for example, if a config key without a label is modified, the change to this key will only
> be reflected in the workload service if the sentinel key value for the environment that the service is running, has also been modified.

> [!NOTE]
> For general guidance see:
> * [Use labels to provide per-environment configuration values](https://learn.microsoft.com/en-us/azure/azure-app-configuration/howto-labels-aspnet-core)
> * [Configuration in ASP.NET Core](https://learn.microsoft.com/en-us/aspnet/core/fundamentals/configuration)

Consider what environments you want the configuration key to be loaded for. As per the above sections:

* there can be a separate store for prod+staging, and another for all other environments
* labels can be assigned to target specific environments served by that store

Once you have identified the correct store, you will need to ensure you have permissions to manage the flags in that store.
You will need Azure RBAC role [App Configuration Contributor](https://learn.microsoft.com/en-us/azure/azure-app-configuration/concept-enable-rbac#control-plane-access) for that store. Typically, this permission is granted
as part of assigning Azure permissions as explained in the section [Granting access to Azure or Power-BI resources](deploy-app.md#granting-access-to-azure-or-power-bi-resources).
The access level required:

* prod and staging environments: "App Admin / support-tier-2"
* dev/test including demo: "development" or "App Admin / support-tier-2"

Now that you've identified the config store and the label(s) to assign to the configuration key(s):

1. Browse to the "Operations" > "Configuration explorer" blade on the Azure app config service in the Azure portal
2. Select "+Create" > "Key-Value" menu item and supply the following:
   * "Key": the exact name used as the key in code for the workload service. This name is likely going to be prefixed
     with a section that the key belongs to. For example "Api:TokenProvider:Authority"
   * "Value": the value for the key
   * "Label": the label that identifies the environment(s) the key should apply. Remember, that no label will cause the
     key to apply to all environments served by that store
   * "Content type": leave blank unless you're defining say a JSON object, in which case set to "application/json"
     For more information see: [Create JSON key-values in App Configuration](https://learn.microsoft.com/en-us/azure/azure-app-configuration/howto-leverage-json-content-type#create-json-key-values-in-app-configuration)
3. As required add a labelled value to the Key-Value - select "..." > "Add value" menu item and supply the following:
   * "Value": the value for the key
   * "Label": the label that identifies the environment(s) the key should apply
   * "Content type": leave blank unless you're defining say a JSON object, in which case set to "application/json"
4. Change the sentinel key value for the to cause the changes to be reflected in the workload service:
   * Find the sentinel key for the environment you want the changes to be reflected in. EG key named "SentinelKey" with 
     label "prod-na" for the prod-na environment
   * Select the "..." > "Edit" menu item for the labelled sentinel key value
   * Change the value to something else, and select "Apply" button
   * Repeat the above for each environment that the changes to keys will need to be reflected in