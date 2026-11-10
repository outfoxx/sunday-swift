Sunday 🙏 The framework of REST for Swift
===

![GitHub Workflow Status](https://img.shields.io/github/actions/workflow/status/outfoxx/sunday-swift/build-test.yml?branch=main)
![Coverage](https://sonarcloud.io/api/project_badges/measure?project=outfoxx_sunday-swift&metric=coverage)
[![](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2Foutfoxx%2Fsunday-swift%2Fbadge%3Ftype%3Dswift-versions)](https://swiftpackageindex.com/outfoxx/sunday-swift)
[![](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2Foutfoxx%2Fsunday-swift%2Fbadge%3Ftype%3Dplatforms)](https://swiftpackageindex.com/outfoxx/sunday-swift)


Swift framework for generated REST clients.

### [Read the Documentation](https://outfoxx.github.io/sunday)

---

Swift Package Manager
---------------------

Sunday is delivered as a Swift package using the Swift Package Manager.

SPM dependency declaration:

```swift
.package(name: "Sunday", url: "https://github.com/outfoxx/sunday-swift.git", from: <version>),
```


Environment-aware credentials
-----------------------------

Generated clients select operation security from an explicitly selected profile. Register
providers under the names in those bindings and pass them to `URLSessionTransport`.
Secrets, interactive authorization, and token persistence remain application responsibilities.

```swift
let provider = try URLSessionOAuthTokenProvider(configuration: .init(
  identity: "external-service", clientID: applicationClientID,
  clientSecret: applicationClientSecret, authentication: .clientSecretBasic
))
let tokens = try TokenManager(provider: provider)
let transport = URLSessionTransport(baseURL: "https://api.example.com", tokenProviders: ["external": tokens])
```

The native provider supports client credentials and application-managed authorization
code/PKCE. For an interactive session, supply a distinct `grantIdentity` and an `authorize`
callback returning `AuthorizationGrant` with a fresh code, redirect URI, and verifier. A
session that cannot refresh throws `AuthorizationRequiredError`; consumed codes are never
reused. External/static credentials implement `TokenProvider`; providers supporting refresh
also implement `RefreshingTokenProvider`.

The actor-based manager partitions tokens by provider/client identity, profile, endpoints,
scopes, audience/resource, and grant identity. It coalesces renewal, applies expiry skew,
preserves rotated refresh tokens, and lets individual callers cancel without interrupting
other waiters. Canceling the last waiter cancels acquisition. Use `TokenStore` for custom
persistence, and call `await tokens.close()` when its application/session ends. Expiry uses
`Date` values. Endpoint overrides change acquisition without rewriting issuer trust.

Credential-bearing requests suppress native redirects and ambient authentication. One recovery is
allowed for an explicit Bearer `invalid_token` challenge on a bodyless GET, HEAD, or OPTIONS.
403 responses and unsafe/body-carrying requests do not replay. Event subscriptions share
one recovery budget across reconnects, and closing a subscription cancels pending acquisition.

Model validation
----------------

Generated models use one hierarchy for reads, storage, editing, and subsequent requests.
Call `model.isValid(.request)` or `try model.validate(.request)` before submitting a value;
use `.response` for received/emitted responses. Generated type-associated validators such as
`ItemValidation` also expose these calls, including for aliases and collection schemas.

Request mode rejects declared enum/union fallbacks by default. Response mode retains the
schema's declared tolerance. Validation never applies defaults or changes the value, and
validity is not cached. `validate` collects stable reason codes and wire paths during the
same canonical check used by `isValid`; `ModelValidationError.diagnostics` provides those
failures as JSON Pointers. Shared references are allowed, while object cycles are rejected.
Generated transport hooks revalidate current values immediately before encoding on every
execution. Constructors and standalone Codable adapters use response semantics.

License
-------

    Copyright 2021 Outfox, Inc.

    Licensed under the Apache License, Version 2.0 (the "License");
    you may not use this file except in compliance with the License.
    You may obtain a copy of the License at

       http://www.apache.org/licenses/LICENSE-2.0

    Unless required by applicable law or agreed to in writing, software
    distributed under the License is distributed on an "AS IS" BASIS,
    WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
    See the License for the specific language governing permissions and
    limitations under the License.

Credentials are isolated by logical security scheme as well as provider and acquisition inputs.
Discovery metadata is fetched and verified on each acquisition or renewal. Temporary provider outages
allow event connections to reconnect; a rejected refresh grant triggers fresh client credentials only
for the client-credentials flow. Interactive sessions require fresh application authorization.
Built-in OAuth providers retain at most 1,024 consumed authorization-code hashes per provider instance.
After this limit, create a provider for a newly authorized application session; old hashes are never
evicted to allow code reuse. Refresh exchanges do not consume this history.

### Typed request parameters

`parameterValidation` is an optional callback on the request specification. The transport invokes it
before encoding on every request build, including bodyless requests and event streams. Generated
callbacks validate captured typed parameters in request mode; reusing an operation checks mutable
values again. Custom transports must call `OperationSpec.validateParameters()` before parameter encoding. Failures
use `SundayError.requestEncodingFailed(.parameterValidationFailed(error:))` and stop SSE reconnection.

## Partial updates

Use non-optional `UpdateOp<Value>` for members that cannot be deleted and `PatchOp<Value>` for
members that can. Both default to `.unchanged` in generated models. `.set(value)` supplies an update;
`PatchOp.delete` writes JSON null to delete the member. Requiredness determines deletion permission,
independently of value nullability. Use non-optional value types: JSON Merge Patch cannot assign a
literal null to an object member.

```swift
struct ItemPatch: Codable {
  var name: UpdateOp<String> = .unchanged
  var note: PatchOp<String> = .unchanged
}
var patch = ItemPatch()
patch.name = .set("Updated")
patch.note = .delete
patch.name = .unchanged // Cancel the name update.
```

Synthesized Codable and the keyed `decode`/`encode` overloads preserve omitted, set, and deleted
states. Encoding `.unchanged` outside a keyed member throws, because it has no standalone JSON
representation. Encoding `.set(nil)` also throws; it must never silently become deletion.
`use` skips unchanged operations, and `get` returns nil for them. Legacy optional-operation
`decodeIfExists`/`encodeIfExists` helpers remain available: nil and `.unchanged` both omit the member,
while `.delete` preserves JSON null. Synthesized encoding also omits nil optional properties, but
a standalone nil optional encodes as JSON null without invoking the operation's encoder. Use
non-optional operations to retain explicit patch states.

## URI template variables

`URI.Template.complete` expands missing and `nil` variables as undefined under RFC 6570.
For an undefined `id`, `/items{/id}` becomes `/items`, while `/items/{id}` becomes
`/items/` because the literal slash remains. Empty strings remain defined: an empty
`id` in `/items{/id}` produces `/items/`. Explicit `nil` overrides a parameter
stored on the template; omitting the override keeps the stored value. This applies
to template expressions in both the base URI and the operation path.

URI-template expansion does not enforce API-required inputs. Callers must validate
any values their API requires before constructing a request. For example, omitting
`env` from `https://{env}example.com` produces `https://example.com`.

## Request and response adapters

Transports adapt each managed attempt in this order:

```text
Prepare request → adapt(request:) → send → adapt(response:for:) → validation and retry policy
```

`RequestAdapter` has one requirement:

```swift
func adapt(request: URLRequest) async throws -> URLRequest
```

`ResponseAdapter` has one requirement:

```swift
func adapt(response: HTTPURLResponse, for request: URLRequest) async throws -> HTTPURLResponse
```

The response adapter receives the actual adapted request sent for that attempt, including its original
credential context. The hook runs for every received response, including unsafe-to-retry requests,
the last permitted attempt, and event-stream handshakes. It transforms native response metadata;
it does not consume the response body.

Pass independent `requestAdapter:` and `responseAdapter:` values to `URLSessionTransport`.
Neither slot infers behavior from the other, even when an adapter implements both protocols.
Use `chain(to:)` to explicitly compose adapters on either side. `RequestAdapters` and
`ResponseAdapters` also accept ordered arrays or variadic arguments. Compositions flatten existing
chains, pass each result to the next adapter, and stop on the first thrown error.

```swift
let authentication = AuthenticationAdapter(providers: ["identity": externalProvider])
let transport = URLSessionTransport(
  baseURL: baseURL,
  requestAdapter: authentication.chain(to: requestHeaders),
  responseAdapter: authentication.chain(to: responseLogger)
)
```

Adapters run again for each retry, followed redirect, and SSE reconnect. Request adaptation starts
from the prepared request each time, so edits do not accumulate. Execution passes adapters directly;
requests carry no pipeline or execution configuration. Buffered responses collect native `Data`
chunks after the response hook accepts the headers, without iterating over individual bytes.

An adapter owns any resources it consumes. It must return a complete request ready to send; if it
reads a body stream, it must provide a replacement stream or body before returning. Sunday does not
reconstruct consumed resources on the adapter's behalf. Replacing a stream drops any inherited
replay factory for the old body. Use `request.with(streamingBody:)` to supply an adapter-owned
replacement factory when the exported request needs native replay support.

Native copy and mutation helpers preserve fields that an adapter does not change:

```swift
let outbound = request.clone {
  $0.timeoutInterval = 123
  $0.httpBody = replacementData
}.setting(header: "X-Request-ID", value: requestID)

let inbound = try response.clone(statusCode: 303)
  .setting(header: "Location", value: "/next")
```

`URLRequest.clone` copies the complete native request and applies an optional mutation closure.
`URLResponse.clone()` preserves the concrete native response type; `HTTPURLResponse.clone(url:statusCode:headers:)`
rebuilds its public HTTP metadata with selected replacements. Both HTTP request and response helpers
support `setting(header:value:)`, `adding(header:value:)`, and `removing(header:)`. Header names are
matched case-insensitively; `adding` is for list-valued headers.

Cloning a request does not read or duplicate its body stream. Use `replayingBody()` for an independent
stream from the installed factory; it throws for a one-shot stream without a factory. Replacing a
body through `clone`, `with(httpBody:)`, or `with(streamingBody:)` removes obsolete replay metadata.
The adapter remains responsible for returning a usable body and any other coordinated changes.

The execution loop applies ordinary redirect rules to the adapted response. It does not try to
validate every possible adapter transformation. A session delegate's accepted redirect request is
preserved in full and becomes the next prepared request, including its replacement body and native
settings. Request adapters run again before that request is sent.

An error conforming to `RequestCancellationError` is an unconditional stop signal:

```swift
struct LoginRequired: RequestCancellationError {}
```

Sunday closes operation-owned resources, stops retries and reconnections, and propagates the original
error unchanged. Swift's `CancellationError` has the same stop behavior. Other failures remain subject
to normal response handling and retry policy; absence of the marker does not authorize a retry.

`AuthenticationAdapter(providers:)` implements both hooks. It acquires credentials once per attempt
and reports rejected bearer tokens to the original provider before the transport considers retrying.
A rejected POST invalidates the token without replaying the POST. A rejection after the retry budget
is exhausted still invalidates the final token. Late responses cannot invalidate a different token
already installed by the manager. Providers unable to recover produce `TokenRejectedError`, which
conforms to `RequestCancellationError`.

```swift
let authentication = AuthenticationAdapter(providers: ["identity": externalProvider])
let transport = URLSessionTransport(
  baseURL: baseURL, requestAdapter: authentication, responseAdapter: authentication
)
```

Generated operation bindings are exposed through `URLRequest.securityBindings` for adapters.
Credential receipts and execution state remain private and are never sent on the wire. The
`tokenProviders:` initializer argument and `URLSessionTransport(settings:)` remain convenience paths
that explicitly compose an authentication adapter on both sides; they do not create a manager or
cache. When combined with custom adapters, authentication runs first on both the request and response
side. Credential-bearing requests suppress native redirects and ambient authentication; adding an
unrelated adapter does not enable this policy. Other redirects honor the session delegate's decision
and run through both hooks for each attempt, with a limit of 20 redirects.

Request exports adapt once and return the caller-owned native request without Sunday response or retry
state. Sending that exported request does not invoke these managed hooks again.

### Swift API migration

- Replace `adapter:` with `requestAdapter:`. If the adapter also handles responses, explicitly pass it
  as `responseAdapter:` too. Use `chain(to:)` to add request or response processing.
- Implement `adapt(request:)` instead of `adapt(transport:urlRequest:)`. Capture application
  dependencies explicitly; refreshing-header adapter callbacks now take no transport argument.
- `eventStream` now returns `AsyncThrowingStream<Element, any Error>`. Consume it with
  `for try await`; terminal event errors are no longer silently discarded. Custom `Transport`
  implementations and generated Swift stream return signatures must adopt this type.
- Token acquisition remains the `TokenProvider` supporting contract. Authentication-specific behavior
  is implemented by adapters, keeping the transport's request/response hooks general.

## Application-owned token lifecycle

Transports accept only request and response adapters; they have no token-provider option or authentication retry logic.
The optional `AuthenticationAdapter` bridges named providers to these contracts. Settings factories compose it explicitly
without adding a cache. External authentication frameworks can implement the adapters directly.
An external framework (for example Auth0) remains responsible for storage, renewal and logout.
Return only its access token and optional expiry; keep its refresh token inside that framework.

For Sunday's caching and refresh lifecycle, explicitly supply a `TokenManager` as the provider:

```swift
let tokens = try TokenManager(provider: oauthProvider, store: applicationStore,
                              expirySkew: 30, now: applicationClock)
let settings = try ClientSettings.resolve(
  baseURL: baseURL, alternatives: alternatives,
  credentials: ["identity": ProviderCredentials(provider: tokens)]
)
// Supply an external framework's provider directly instead to keep its lifecycle authoritative.
let transport = URLSessionTransport(settings: settings)
```

Managers retain expiry skew, coalesced renewal, refresh rotation and application-selected persistence.
Call `await tokens.close()` after all clients sharing the manager finish.
Transport closure does not erase the store or close a shared provider. Separate managers do not
coordinate refreshes merely because they share a store. Reuse the same manager across clients that
share a credential lifecycle, and distinguish users/environments with provider and grant identities.

Providers can implement `reject` to handle an invalid bearer token. It receives the original request
context and rejected access token, and returns whether recovery can proceed. Compare the rejected
credential with the current session before renewing: a late rejection must not invalidate a newer token
or a new login. Providers without this capability stop with `TokenRejectedError` and do not automatically retry. Acquisition and rejection
must not start interactive login automatically; return an authorization-required failure to the caller.
For an Auth0 adapter, retrieve through its credentials manager and force renewal through that same
manager on rejection, serializing concurrent rejection handling without maintaining a second token cache.

Request export materializes an optionally authorized native request once and hands its lifecycle to
the consumer. Exported requests retain no Sunday-managed recovery state. Executing an operation through
Sunday invokes the request adapter once per attempt. Authentication responses do not trigger an implicit retry;
an application may make another request after its credential owner handles the rejection.

Migration: replace transport `tokenManager`/`token_manager` and `tokenProviders`/`token_providers` arguments
with explicit request/response adapters. Replace `TokenManagerFactory` hooks with explicitly constructed
managers supplied through provider credentials. Direct built-in OAuth providers are not implicitly cached;
wrap them explicitly when Sunday should retain and refresh their tokens. For logout, stop outstanding
requests and settle refresh commits before clearing the owning framework's or application's storage.
