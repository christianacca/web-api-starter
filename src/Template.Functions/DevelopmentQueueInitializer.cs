using Azure.Storage.Queues;
using Microsoft.Extensions.Azure;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Logging;

namespace Template.Functions;

public class DevelopmentQueueInitializer(
  IAzureClientFactory<QueueServiceClient> queueServiceClientFactory,
  ILogger<DevelopmentQueueInitializer> logger) : IHostedService {

  internal const string QueueClientName = "AzureWebJobsStorageQueues";

  public async Task StartAsync(CancellationToken cancellationToken) {
    var queueServiceClient = queueServiceClientFactory.CreateClient(QueueClientName);

    foreach (var queueName in new[] { ExampleQueue.QueueName, ExampleQueue.PoisonQueueName }) {
      await queueServiceClient.GetQueueClient(queueName).CreateIfNotExistsAsync(cancellationToken: cancellationToken);
      logger.LogInformation("Ensured development queue exists: {QueueName}", queueName);
    }
  }

  public Task StopAsync(CancellationToken cancellationToken) => Task.CompletedTask;
}