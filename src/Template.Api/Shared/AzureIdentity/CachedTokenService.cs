using Azure.Core;
using Azure.Identity;

namespace Template.Api.Shared.AzureIdentity;

public class CachedTokenService : ITokenService {
  private TokenRequestContext Context { get; }
  private AccessTokenCache TokenCache { get; }

  public CachedTokenService(string audience, DefaultAzureCredentialOptions credentialsOptions) {
    var credential = new DefaultAzureCredential(credentialsOptions);
    Context = new TokenRequestContext(new[] { audience });
    TokenCache = new AccessTokenCache(credential, TimeSpan.FromMinutes(5), TimeSpan.FromSeconds(30));
  }

  public virtual async ValueTask<string> GetTokenAsync(
    CancellationToken cancellationToken = default) {
    return await TokenCache.GetHeaderValueAsync(cancellationToken, Context, true);
  }

  /// <summary>
  /// Copied from https://github.com/Azure/azure-sdk-for-net/blob/800851eaad8f9a4a7ef0cf12c4fa764748304559/sdk/core/Azure.Core/src/Pipeline/BearerTokenAuthenticationPolicy.cs#L176
  /// </summary>
  /// <remarks>
  /// We're copying this class in-lieu of a caching implementation being added to ManagedIdentityCredential. see:
  /// https://github.com/Azure/azure-sdk-for-net/issues/25361
  /// TODO: once official caching added to ManagedIdentityCredential, remove this class (and probably CachedTokenService)
  /// </remarks>
  private class AccessTokenCache {
    private readonly object _syncObj = new object();
    private readonly TokenCredential _credential;
    private readonly TimeSpan _tokenRefreshOffset;
    private readonly TimeSpan _tokenRefreshRetryDelay;

    // must be updated under lock (_syncObj)
    private TokenRequestState? _state;

    public AccessTokenCache(TokenCredential credential, TimeSpan tokenRefreshOffset, TimeSpan tokenRefreshRetryDelay) {
      _credential = credential;
      _tokenRefreshOffset = tokenRefreshOffset;
      _tokenRefreshRetryDelay = tokenRefreshRetryDelay;
    }

    public async ValueTask<string> GetHeaderValueAsync(CancellationToken ct, TokenRequestContext context, bool async) {
      bool getTokenFromCredential;
      TaskCompletionSource<HeaderValueInfo> headerValueTcs;
      TaskCompletionSource<HeaderValueInfo>? backgroundUpdateTcs;
      int maxCancellationRetries = 3;

      while (true) {
        (headerValueTcs, backgroundUpdateTcs, getTokenFromCredential) = GetTaskCompletionSources(context);
        HeaderValueInfo info;
        if (getTokenFromCredential) {
          if (backgroundUpdateTcs != null) {
            if (async) {
              info = await headerValueTcs.Task.ConfigureAwait(false);
            } else {
#pragma warning disable AZC0104 // Use EnsureCompleted() directly on asynchronous method return value.
              info = headerValueTcs.Task.EnsureCompleted();
#pragma warning restore AZC0104 // Use EnsureCompleted() directly on asynchronous method return value.
            }

            _ = Task.Run(() =>
              GetHeaderValueFromCredentialInBackgroundAsync(backgroundUpdateTcs, info, context, async));
            return info.HeaderValue;
          }

          try {
            info = await GetHeaderValueFromCredentialAsync(context, async, ct).ConfigureAwait(false);
            headerValueTcs.SetResult(info);
          }
          catch (OperationCanceledException) {
            headerValueTcs.SetCanceled();
          }
          catch (Exception exception) {
            headerValueTcs.SetException(exception);
            // The exception will be thrown on the next lines when we touch the result of
            // headerValueTcs.Task, this approach will prevent later runtime UnobservedTaskException
          }
        }

        var headerValueTask = headerValueTcs.Task;
        try {
          if (!headerValueTask.IsCompleted) {
            if (async) {
              await headerValueTask.AwaitWithCancellation(ct);
            } else {
              try {
                headerValueTask.Wait(ct);
              }
              catch (AggregateException) {
              } // ignore exception here to rethrow it with EnsureCompleted
            }
          }

          if (async) {
            info = await headerValueTcs.Task.ConfigureAwait(false);
          } else {
#pragma warning disable AZC0104 // Use EnsureCompleted() directly on asynchronous method return value.
            info = headerValueTcs.Task.EnsureCompleted();
#pragma warning restore AZC0104 // Use EnsureCompleted() directly on asynchronous method return value.
          }

          return info.HeaderValue;
        }
        catch (TaskCanceledException) when (!ct.IsCancellationRequested) {
          maxCancellationRetries--;

          // If the current message has no CancellationToken and we have tried this 3 times, throw.
          if (!ct.CanBeCanceled && maxCancellationRetries <= 0) {
            throw;
          }

          // We were waiting on a previous headerValueTcs operation which was canceled.
          //Retry the call to GetTaskCompletionSources.
          continue;
        }
      }
    }

    private (TaskCompletionSource<HeaderValueInfo> InfoTcs, TaskCompletionSource<HeaderValueInfo>? BackgroundUpdateTcs,
      bool GetTokenFromCredential)
      GetTaskCompletionSources(TokenRequestContext context) {
      // Check if the current state requires no updates to _state under lock and is valid.
      // All checks must be done on the local prefixed variables as _state can be modified by other threads.
      var localState = _state;
      if (localState != null && localState.InfoTcs.Task.IsCompleted && !localState.RequestRequiresNewToken(context)) {
        DateTimeOffset now = DateTimeOffset.UtcNow;
        if (!localState.BackgroundTokenAcquiredSuccessfully(now) && !localState.AccessTokenFailedOrExpired(now) &&
            !localState.TokenNeedsBackgroundRefresh(now)) {
          // localState entity has a valid token, no need to enter lock.
          return (localState.InfoTcs, default, false);
        }
      }

      lock (_syncObj) {
        // Initial state. GetTaskCompletionSources has been called for the first time
        if (_state == null || _state.RequestRequiresNewToken(context)) {
          _state = new TokenRequestState(context,
            new TaskCompletionSource<HeaderValueInfo>(TaskCreationOptions.RunContinuationsAsynchronously), default);
          return (_state.InfoTcs, _state.BackgroundUpdateTcs, true);
        }

        // Getting new access token is in progress, wait for it
        if (!_state.InfoTcs.Task.IsCompleted) {
          // Only create new TokenRequestState if necessary.
          if (_state.BackgroundUpdateTcs != null) {
            _state = new TokenRequestState(_state.CurrentContext, _state.InfoTcs, default);
          }

          return (_state.InfoTcs, _state.BackgroundUpdateTcs, false);
        }

        DateTimeOffset now = DateTimeOffset.UtcNow;
        // Access token has been successfully acquired in background and it is not expired yet, use it instead of current one
        if (_state.BackgroundTokenAcquiredSuccessfully(now)) {
          _state = new TokenRequestState(_state.CurrentContext, _state.BackgroundUpdateTcs!, default);
        }

        // Attempt to get access token has failed or it has already expired. Need to get a new one
        if (_state.AccessTokenFailedOrExpired(now)) {
          _state = new TokenRequestState(_state.CurrentContext,
            new TaskCompletionSource<HeaderValueInfo>(TaskCreationOptions.RunContinuationsAsynchronously),
            _state.BackgroundUpdateTcs);
          return (_state.InfoTcs, default, true);
        }

        // Access token is still valid but is about to expire, try to get it in background
        if (_state.TokenNeedsBackgroundRefresh(now)) {
          _state = new TokenRequestState(_state.CurrentContext, _state.InfoTcs,
            new TaskCompletionSource<HeaderValueInfo>(TaskCreationOptions.RunContinuationsAsynchronously));
          return (_state.InfoTcs, _state.BackgroundUpdateTcs, true);
        }

        // Access token is valid, use it
        return (_state.InfoTcs, default, false);
      }
    }

    private async ValueTask GetHeaderValueFromCredentialInBackgroundAsync(
      TaskCompletionSource<HeaderValueInfo> backgroundUpdateTcs,
      HeaderValueInfo info,
      TokenRequestContext context,
      bool async) {
      var cts = new CancellationTokenSource(_tokenRefreshRetryDelay);
      try {
        HeaderValueInfo newInfo =
          await GetHeaderValueFromCredentialAsync(context, async, cts.Token).ConfigureAwait(false);
        backgroundUpdateTcs.SetResult(newInfo);
      }
      catch (OperationCanceledException) when (cts.IsCancellationRequested) {
        backgroundUpdateTcs.SetResult(new HeaderValueInfo(info.HeaderValue, info.ExpiresOn, DateTimeOffset.UtcNow));
        // AzureCoreEventSource.Singleton.BackgroundRefreshFailed(context.ParentRequestId ?? string.Empty, oce.ToString());
      }
      catch (Exception) {
        backgroundUpdateTcs.SetResult(new HeaderValueInfo(info.HeaderValue, info.ExpiresOn,
          DateTimeOffset.UtcNow + _tokenRefreshRetryDelay));
        // AzureCoreEventSource.Singleton.BackgroundRefreshFailed(context.ParentRequestId ?? string.Empty, e.ToString());
      }
      finally {
        cts.Dispose();
      }
    }

    private async ValueTask<HeaderValueInfo> GetHeaderValueFromCredentialAsync(TokenRequestContext context, bool async,
      CancellationToken cancellationToken) {
      AccessToken token = async
        ? await _credential.GetTokenAsync(context, cancellationToken).ConfigureAwait(false)
        : _credential.GetToken(context, cancellationToken);

      return new HeaderValueInfo(token.Token, token.ExpiresOn, token.ExpiresOn - _tokenRefreshOffset);
    }

    private readonly struct HeaderValueInfo {
      public string HeaderValue { get; }
      public DateTimeOffset ExpiresOn { get; }
      public DateTimeOffset RefreshOn { get; }

      public HeaderValueInfo(string headerValue, DateTimeOffset expiresOn, DateTimeOffset refreshOn) {
        HeaderValue = headerValue;
        ExpiresOn = expiresOn;
        RefreshOn = refreshOn;
      }
    }

    private class TokenRequestState {
      public TokenRequestContext CurrentContext { get; }
      public TaskCompletionSource<HeaderValueInfo> InfoTcs { get; }
      public TaskCompletionSource<HeaderValueInfo>? BackgroundUpdateTcs { get; }

      public TokenRequestState(TokenRequestContext currentContext, TaskCompletionSource<HeaderValueInfo> infoTcs,
        TaskCompletionSource<HeaderValueInfo>? backgroundUpdateTcs) {
        CurrentContext = currentContext;
        InfoTcs = infoTcs;
        BackgroundUpdateTcs = backgroundUpdateTcs;
      }

      public bool RequestRequiresNewToken(TokenRequestContext context) =>
        (context.Scopes != null && !context.Scopes.AsSpan().SequenceEqual(CurrentContext.Scopes.AsSpan())) ||
        (context.Claims != null && !string.Equals(context.Claims, CurrentContext.Claims));

      public bool BackgroundTokenAcquiredSuccessfully(DateTimeOffset now) =>
        BackgroundUpdateTcs != null &&
        BackgroundUpdateTcs.Task.Status == TaskStatus.RanToCompletion &&
        BackgroundUpdateTcs.Task.Result.ExpiresOn > now;

      public bool AccessTokenFailedOrExpired(DateTimeOffset now) =>
        InfoTcs.Task.Status != TaskStatus.RanToCompletion || now >= InfoTcs.Task.Result.ExpiresOn;

      public bool TokenNeedsBackgroundRefresh(DateTimeOffset now) =>
        now >= InfoTcs.Task.Result.RefreshOn && BackgroundUpdateTcs == null;
    }
  }
}