Remove-Item -Force -ErrorAction Continue ./obj/CreateOrUpdateDb.sql
dotnet ef migrations script -i -o obj/CreateOrUpdateDb.sql -p src/Template.Shared -s src/Template.Api