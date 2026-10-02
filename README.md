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
providers under the names in those bindings and pass the manager to `URLSessionTransport`.
Secrets, interactive authorization, and token persistence remain application responsibilities.

```swift
let provider = try URLSessionOAuthTokenProvider(configuration: .init(
  identity: "external-service", clientID: applicationClientID,
  clientSecret: applicationClientSecret, authentication: .clientSecretBasic
))
let tokens = try TokenManager(providers: ["external": provider])
let transport = URLSessionTransport(baseURL: "https://api.example.com", tokenManager: tokens)
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

Managed requests suppress native redirects and ambient authentication. One recovery is
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

Use `UpdateOp<Value>?` for fields that can be set but not deleted, and `PatchOp<Value>?` for fields
that can also be deleted. `nil` leaves the field unchanged, `.set(value)` supplies an update, and
`.delete` writes JSON null to delete a member. Use non-optional value types for JSON Merge Patch;
whether a member may be removed is independent of whether its value may be null.
Decode with `decodeIfExists` and encode with
`encodeIfExists` to retain these states. A present null for a non-optional `UpdateOp` value throws a
`DecodingError` with the field's coding path; it is never silently treated as omission.
