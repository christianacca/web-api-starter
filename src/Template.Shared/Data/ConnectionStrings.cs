using Microsoft.Data.SqlClient;
using Microsoft.Extensions.Configuration;

namespace Template.Shared.Data;

public static class ConnectionStrings {
  public static string GetDefaultConnectionString(this IConfiguration configuration) {
    const string dbKey = "AppDatabase";
    var connectionString = configuration.GetConnectionString(dbKey);
    if (!string.IsNullOrWhiteSpace(connectionString)) {
      return connectionString;
    }

    var configSection = configuration.GetSection("Database");
    if (!configSection.Exists() || configSection.GetChildren().All(x => string.IsNullOrWhiteSpace(x.Value))) {
      throw new ArgumentException(
        $"Missing configuration to build the connection string. Looked for 'ConnectionStrings:{dbKey}' and 'Database' section values");
    }

    var connectionStringBuilder = new SqlConnectionStringBuilder {
      // recommended defaults for azure sql db...
      Encrypt = true, ConnectTimeout = 30
    };
    configSection.Bind(connectionStringBuilder);
    return connectionStringBuilder.ConnectionString;
  }
}