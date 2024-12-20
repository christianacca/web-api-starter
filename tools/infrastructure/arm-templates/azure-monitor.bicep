@metadata({ Description: 'Email address to send notification of critical alerts' })
param alertEmailCritical string

@metadata({ Description: 'Email address to send notification of non-critical alerts' })
param alertEmailNonCritical string

@description('Name of Application Insights resource.')
param appInsightsName string = 'appi-${appName}${environmentName}'

@metadata({ Description: 'The name of the application whose alerts are being generated. EG \'platform-x\'' })
param appName string

@description('Enable metric based alerts?')
param enableMetricAlerts bool = true

@metadata({ Description: 'A short abbreviation (max 6 characters) for the environment name for the application, EG \'emea\'' })
@maxLength(6)
param environmentAbbreviation string

@metadata({ Description: 'The environment name for the application, EG \'prod-emea\'' })
param environmentName string

@description('Specify the log analytics workspace and related components.')
param location string = resourceGroup().location

@description('Specify the number of days to retain data.')
param retentionInDays int = 30

@description('Specify the name of the log analytics workspace.')
param workspaceName string = 'log-${appName}${environmentName}'

@description('Default availability health checks to create.')
param defaultAvailabilityTests array = []

@description('Specify the pricing tier: PerGB2018 or legacy tiers (Free, Standalone, PerNode, Standard or Premium) which are not available to all customers.')
@allowed([
  'CapacityReservation'
  'Free'
  'LACluster'
  'PerGB2018'
  'PerNode'
  'Premium'
  'Standalone'
  'Standard'
])
param workspaceSku string = 'PerGB2018'

var actionGroupNamePrefix = '${appName}-${environmentName}'
var nonCriticalActionGroupName = '${actionGroupNamePrefix}-non-critical'
var criticalActionGroupName = '${actionGroupNamePrefix}-critical'

resource workspace 'Microsoft.OperationalInsights/workspaces@2021-12-01-preview' = {
  name: workspaceName
  location: location
  properties: {
    sku: {
      name: workspaceSku
    }
    retentionInDays: retentionInDays
    features: {
      enableLogAccessUsingOnlyResourcePermissions: true
    }
    workspaceCapping: {
      dailyQuotaGb: 3
    }
    publicNetworkAccessForIngestion: 'Enabled'
    publicNetworkAccessForQuery: 'Enabled'
  }
}

resource appInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: appInsightsName
  location: location
  kind: 'web'
  properties: {
    Application_Type: 'web'
    Flow_Type: 'Redfield'
    Request_Source: 'CustomDeployment'
    RetentionInDays: 90
    WorkspaceResourceId: workspace.id
    IngestionMode: 'LogAnalytics'
    publicNetworkAccessForIngestion: 'Enabled'
    publicNetworkAccessForQuery: 'Enabled'
  }
}

module webTests 'br/public:avm/res/insights/webtest:0.3.0' = [for (webTest, i) in defaultAvailabilityTests: {
  name: '${uniqueString(deployment().name, location)}-${i}-WebTest'
  params: {
    appInsightResourceId: appInsights.id
    enabled: webTest.Enabled
    frequency: webTest.Frequency
    name: webTest.ResourceName
    locations: webTest.Locations == null ? null : map(webTest.Locations, testLocation => {
      Id: testLocation
    })
    request: {
      HttpVerb: 'GET'
      RequestUrl: webTest.RequestUrl
    }
    validationRules: {
      ExpectedHttpStatusCode: 200
      IgnoreHttpStatusCode: false
      ContentValidation: {
        ContentMatch: 'Healthy'
        IgnoreCase: true
        PassIfTextFound: true
      }
      SSLCheck: true
      SSLCertRemainingLifetimeCheck: 7
    }
    webTestName: webTest.Name
  }
}]

resource webTestAlerts 'Microsoft.Insights/metricAlerts@2018-03-01' = [for (webTest, i) in defaultAvailabilityTests: {
  name: webTest.MetricAlert.ResourceName
  location: 'global'
  properties: {
    criteria: {
      webTestId: webTests[i].outputs.resourceId
      componentId: appInsights.id
      failedLocationCount: webTest.MetricAlert.FailedLocationCount
      'odata.type': 'Microsoft.Azure.Monitor.WebtestLocationAvailabilityCriteria'
    }
    description: webTest.MetricAlert.Description
    enabled: webTest.MetricAlert.Enabled && enableMetricAlerts
    evaluationFrequency: webTest.MetricAlert.EvaluationFrequency
    scopes: [
      webTests[i].outputs.resourceId
      appInsights.id
    ]
    severity: 1
    windowSize: webTest.MetricAlert.WindowSize
  }
}]

resource requestPerformanceDegradationDetectorRule 'Microsoft.AlertsManagement/smartdetectoralertrules@2021-04-01' = {
  name: 'Response Latency Degradation - ${appInsightsName}'
  location: 'global'
  properties: {
    description: 'Response Latency Degradation notifies you of an unusual increase in latency in your app response to requests.'
    state: 'Enabled'
    severity: 'Sev3'
    frequency: 'P1D'
    detector: {
      id: 'RequestPerformanceDegradationDetector'
    }
    scope: [
      appInsights.id
    ]
    actionGroups: {
      groupIds: []
    }
  }
}

resource dependencyPerformanceDegradationDetectorRule 'Microsoft.AlertsManagement/smartdetectoralertrules@2021-04-01' = {
  name: 'Dependency Latency Degradation - ${appInsightsName}'
  location: 'global'
  properties: {
    description: 'Dependency Latency Degradation notifies you of an unusual increase in response by a dependency your app is calling (e.g. REST API or database)'
    state: 'Enabled'
    severity: 'Sev3'
    frequency: 'P1D'
    detector: {
      id: 'DependencyPerformanceDegradationDetector'
    }
    scope: [
      appInsights.id
    ]
    actionGroups: {
      groupIds: []
    }
  }
}

resource traceSeverityDetectorRule 'Microsoft.AlertsManagement/smartdetectoralertrules@2021-04-01' = {
  name: 'Trace Severity Degradation - ${appInsightsName}'
  location: 'global'
  properties: {
    description: 'Trace Severity Degradation notifies you of an unusual increase in the severity of the traces generated by your app.'
    state: 'Enabled'
    severity: 'Sev3'
    frequency: 'P1D'
    detector: {
      id: 'TraceSeverityDetector'
    }
    scope: [
      appInsights.id
    ]
    actionGroups: {
      groupIds: []
    }
  }
}

resource exceptionVolumeChangedDetectorRule 'Microsoft.AlertsManagement/smartdetectoralertrules@2021-04-01' = {
  name: 'Exception Anomalies - ${appInsightsName}'
  location: 'global'
  properties: {
    description: 'Exception Anomalies notifies you of an unusual rise in the rate of exceptions thrown by your app.'
    state: 'Enabled'
    severity: 'Sev3'
    frequency: 'P1D'
    detector: {
      id: 'ExceptionVolumeChangedDetector'
    }
    scope: [
      appInsights.id
    ]
    actionGroups: {
      groupIds: []
    }
  }
}

resource memoryLeakRule 'Microsoft.AlertsManagement/smartdetectoralertrules@2021-04-01' = {
  name: 'Potential Memory Leak - ${appInsightsName}'
  location: 'global'
  properties: {
    description: 'Potential Memory Leak notifies you of increased memory consumption pattern by your app which may indicate a potential memory leak.'
    state: 'Enabled'
    severity: 'Sev3'
    frequency: 'P1D'
    detector: {
      id: 'MemoryLeakDetector'
    }
    scope: [
      appInsights.id
    ]
    actionGroups: {
      groupIds: []
    }
  }
}

resource failureAnomaliesRule 'Microsoft.AlertsManagement/smartdetectoralertrules@2021-04-01' = {
  name: 'Failure Anomalies - ${appInsightsName}'
  location: 'global'
  properties: {
    description: 'Failure Anomalies notifies you of an unusual rise in the rate of failed HTTP requests or dependency calls.'
    state: 'Enabled'
    severity: 'Sev3'
    frequency: 'PT1M'
    detector: {
      id: 'FailureAnomaliesDetector'
    }
    scope: [
      appInsights.id
    ]
    actionGroups: {
      groupIds: []
    }
  }
}

resource migrationToAlertRulesCompleted 'Microsoft.Insights/components/ProactiveDetectionConfigs@2018-05-01-preview' = {
  parent: appInsights
  name: 'migrationToAlertRulesCompleted'
  location: location
  properties: {
    SendEmailsToSubscriptionOwners: false
    CustomEmails: []
    Enabled: true
  }
  dependsOn: [
    requestPerformanceDegradationDetectorRule
    dependencyPerformanceDegradationDetectorRule
    traceSeverityDetectorRule
    exceptionVolumeChangedDetectorRule
    memoryLeakRule
  ]
}

resource nonCriticalActionGroup 'microsoft.insights/actionGroups@2019-06-01' = {
  name: nonCriticalActionGroupName
  location: 'Global'
  properties: {
    groupShortName: '${toUpper(environmentAbbreviation)}-NCRIT'
    enabled: true
    emailReceivers: [
      {
        name: 'Primary Email Notification_-EmailAction-'
        emailAddress: alertEmailNonCritical
        useCommonAlertSchema: true
      }
    ]
    smsReceivers: []
    webhookReceivers: []
    itsmReceivers: []
    azureAppPushReceivers: []
    automationRunbookReceivers: []
    voiceReceivers: []
    logicAppReceivers: []
    azureFunctionReceivers: []
    armRoleReceivers: []
  }
}

resource criticalActionGroup 'microsoft.insights/actionGroups@2019-06-01' = {
  name: criticalActionGroupName
  location: 'Global'
  properties: {
    groupShortName: '${toUpper(environmentAbbreviation)}-CRIT'
    enabled: true
    emailReceivers: [
      {
        name: 'Primary Email Notification_-EmailAction-'
        emailAddress: alertEmailCritical
        useCommonAlertSchema: true
      }
    ]
    smsReceivers: []
    webhookReceivers: []
    itsmReceivers: []
    azureAppPushReceivers: []
    automationRunbookReceivers: []
    voiceReceivers: []
    logicAppReceivers: []
    azureFunctionReceivers: []
    armRoleReceivers: []
  }
}

resource criticalActionGroup_rules 'Microsoft.AlertsManagement/actionRules@2021-08-08' = {
  name: criticalActionGroupName
  location: 'global'
  properties: {
    scopes: [
      appInsights.id
    ]
    conditions: [
      {
        field: 'Severity'
        operator: 'Equals'
        values: [
          'Sev0'
          'Sev1'
        ]
      }
    ]
    enabled: true
    actions: [
      {
        actionGroupIds: [
          criticalActionGroup.id
        ]
        actionType: 'AddActionGroups'
      }
    ]
    description: '${appName} ${environmentName} critical alerts'
  }
}

resource nonCriticalActionGroup_rules 'Microsoft.AlertsManagement/actionRules@2021-08-08' = {
  name: nonCriticalActionGroupName
  location: 'global'
  properties: {
    scopes: [
      appInsights.id
    ]
    conditions: [
      {
        field: 'Severity'
        operator: 'Equals'
        values: [
          'Sev2'
          'Sev3'
        ]
      }
    ]
    enabled: true
    actions: [
      {
        actionGroupIds: [
          nonCriticalActionGroup.id
        ]
        actionType: 'AddActionGroups'
      }
    ]
    description: '${appName} ${environmentName} non-critical alerts'
  }
}

resource browser_exceptions_metricAlert 'microsoft.insights/metricAlerts@2018-03-01' = {
  name: '${appName}-${environmentName}-browser-exceptions'
  location: 'global'
  properties: {
    description: 'Alert when unhandled browser exceptions increases above previously observed behaviour'
    severity: 1
    enabled: enableMetricAlerts
    scopes: [
      appInsights.id
    ]
    evaluationFrequency: 'PT5M'
    windowSize: 'PT15M'
    criteria: {
      allOf: [
        {
          alertSensitivity: 'High'
          failingPeriods: {
            numberOfEvaluationPeriods: 4
            minFailingPeriodsToAlert: 2
          }
          name: 'Metric1'
          metricNamespace: 'microsoft.insights/components'
          metricName: 'exceptions/browser'
          dimensions: [
            {
              name: 'cloud/roleName'
              operator: 'Include'
              values: [
                '*'
              ]
            }
          ]
          operator: 'GreaterThan'
          timeAggregation: 'Count'
          criterionType: 'DynamicThresholdCriterion'
        }
      ]
      'odata.type': 'Microsoft.Azure.Monitor.MultipleResourceMultipleMetricCriteria'
    }
    autoMitigate: false
    actions: []
  }
}

resource dependency_failure_meticAlert 'microsoft.insights/metricAlerts@2018-03-01' = {
  name: '${appName}-${environmentName}-dependency-failure'
  location: 'global'
  properties: {
    description: 'Alert when dependency failures by result code increases above previously observed behaviour'
    severity: 1
    enabled: enableMetricAlerts
    scopes: [
      appInsights.id
    ]
    evaluationFrequency: 'PT5M'
    windowSize: 'PT15M'
    criteria: {
      allOf: [
        {
          alertSensitivity: 'Low'
          failingPeriods: {
            numberOfEvaluationPeriods: 4
            minFailingPeriodsToAlert: 2
          }
          name: 'Metric1'
          metricNamespace: 'Microsoft.Insights/components'
          metricName: 'dependencies/failed'
          dimensions: [
            {
              name: 'dependency/resultCode'
              operator: 'Include'
              values: [
                '*'
              ]
            }
            {
              name: 'cloud/roleName'
              operator: 'Include'
              values: [
                '*'
              ]
            }
          ]
          operator: 'GreaterThan'
          timeAggregation: 'Count'
          criterionType: 'DynamicThresholdCriterion'
        }
      ]
      'odata.type': 'Microsoft.Azure.Monitor.MultipleResourceMultipleMetricCriteria'
    }
    autoMitigate: true
    actions: []
  }
}

resource server_exceptions_meticAlert 'microsoft.insights/metricAlerts@2018-03-01' = {
  name: '${appName}-${environmentName}-server-exceptions'
  location: 'global'
  properties: {
    description: 'Alert when unhandled server exceptions increases above previously observed behaviour'
    severity: 1
    enabled: enableMetricAlerts
    scopes: [
      appInsights.id
    ]
    evaluationFrequency: 'PT5M'
    windowSize: 'PT15M'
    criteria: {
      allOf: [
        {
          alertSensitivity: 'High'
          failingPeriods: {
            numberOfEvaluationPeriods: 4
            minFailingPeriodsToAlert: 2
          }
          name: 'Metric1'
          metricNamespace: 'microsoft.insights/components'
          metricName: 'exceptions/server'
          dimensions: [
            {
              name: 'cloud/roleName'
              operator: 'Include'
              values: [
                '*'
              ]
            }
          ]
          operator: 'GreaterThan'
          timeAggregation: 'Count'
          criterionType: 'DynamicThresholdCriterion'
        }
      ]
      'odata.type': 'Microsoft.Azure.Monitor.MultipleResourceMultipleMetricCriteria'
    }
    autoMitigate: false
    actions: []
  }
}

resource response_time_metricAlert 'microsoft.insights/metricAlerts@2018-03-01' = {
  name: '${appName}-${environmentName}-response-time'
  location: 'global'
  properties: {
    description: 'Alert when server response time increases above previously observed behaviour'
    severity: 2
    enabled: enableMetricAlerts
    scopes: [
      appInsights.id
    ]
    evaluationFrequency: 'PT5M'
    windowSize: 'PT15M'
    criteria: {
      allOf: [
        {
          alertSensitivity: 'Low'
          failingPeriods: {
            numberOfEvaluationPeriods: 4
            minFailingPeriodsToAlert: 2
          }
          name: 'Metric1'
          metricNamespace: 'Microsoft.Insights/components'
          metricName: 'requests/duration'
          dimensions: [
            {
              name: 'cloud/roleName'
              operator: 'Include'
              values: [
                '*'
              ]
            }
          ]
          operator: 'GreaterThan'
          timeAggregation: 'Average'
          criterionType: 'DynamicThresholdCriterion'
        }
      ]
      'odata.type': 'Microsoft.Azure.Monitor.MultipleResourceMultipleMetricCriteria'
    }
    autoMitigate: true
    actions: []
  }
}

resource trace_error_metricAlert 'microsoft.insights/metricAlerts@2018-03-01' = {
  name: '${appName}-${environmentName}-trace-error'
  location: 'global'
  properties: {
    description: 'Alert when high severity traces increases above previously observed behaviour'
    severity: 1
    enabled: enableMetricAlerts
    scopes: [
      appInsights.id
    ]
    evaluationFrequency: 'PT5M'
    windowSize: 'PT15M'
    criteria: {
      allOf: [
        {
          alertSensitivity: 'Medium'
          failingPeriods: {
            numberOfEvaluationPeriods: 4
            minFailingPeriodsToAlert: 2
          }
          name: 'Metric1'
          metricNamespace: 'Microsoft.Insights/components'
          metricName: 'traces/count'
          dimensions: [
            {
              name: 'trace/severityLevel'
              operator: 'Include'
              values: [
                '3'
                '4'
              ]
            }
            {
              name: 'cloud/roleName'
              operator: 'Include'
              values: [
                '*'
              ]
            }
          ]
          operator: 'GreaterThan'
          timeAggregation: 'Count'
          criterionType: 'DynamicThresholdCriterion'
        }
      ]
      'odata.type': 'Microsoft.Azure.Monitor.MultipleResourceMultipleMetricCriteria'
    }
    autoMitigate: false
    actions: []
  }
}

resource warning_traces_metricAlert 'microsoft.insights/metricAlerts@2018-03-01' = {
  name: '${appName}-${environmentName}-warning-traces'
  location: 'global'
  properties: {
    description: 'Alert when warning severity traces increases above previously observed behaviour'
    severity: 2
    enabled: enableMetricAlerts
    scopes: [
      appInsights.id
    ]
    evaluationFrequency: 'PT5M'
    windowSize: 'PT15M'
    criteria: {
      allOf: [
        {
          alertSensitivity: 'Medium'
          failingPeriods: {
            numberOfEvaluationPeriods: 4
            minFailingPeriodsToAlert: 2
          }
          name: 'Metric1'
          metricNamespace: 'Microsoft.Insights/components'
          metricName: 'traces/count'
          dimensions: [
            {
              name: 'trace/severityLevel'
              operator: 'Include'
              values: [
                '2'
              ]
            }
            {
              name: 'cloud/roleName'
              operator: 'Include'
              values: [
                '*'
              ]
            }
          ]
          operator: 'GreaterThan'
          timeAggregation: 'Count'
          criterionType: 'DynamicThresholdCriterion'
        }
      ]
      'odata.type': 'Microsoft.Azure.Monitor.MultipleResourceMultipleMetricCriteria'
    }
    autoMitigate: true
    actions: []
  }
}

@description('The Application Insights resource id.')
output appInsightsResourceId string = appInsights.id

@description('The Application Insights connection string.')
output appInsightsConnectionString string = appInsights.properties.ConnectionString

@description('The Log analytics workspace resource id.')
output logAnalyticsWorkspaceResourceId string = workspace.id
