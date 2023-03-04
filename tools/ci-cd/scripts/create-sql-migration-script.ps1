$Env:Api__KeyVaultDisabled = $true
dotnet ef migrations script -i -o publish/migrate-db.sql -p src/Template.Shared -s src/Template.Api