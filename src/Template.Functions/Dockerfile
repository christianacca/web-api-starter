# **IMPORTANT**
# We're not actually using this dockerfile because we're not deploying our functions to AKS
# but if we did this dockerfile can be used

# To enable ssh & remote debugging on app service change the base image to the one below
# FROM mcr.microsoft.com/azure-functions/dotnet-isolated:4-dotnet-isolated8.0-appservice
FROM mcr.microsoft.com/azure-functions/dotnet-isolated:4-dotnet-isolated8.0
ENV AzureWebJobsScriptRoot=/home/site/wwwroot

WORKDIR /home/site/wwwroot
COPY . .