FROM mcr.microsoft.com/dotnet/aspnet:10.0-noble-chiseled-extra
#EXPOSE 8080 <- this is the default port that a .net 10 application will be configured to listen on and is the port exposed in the base docker image

WORKDIR /app

ENTRYPOINT ["dotnet", "Template.App.dll"]
COPY . .