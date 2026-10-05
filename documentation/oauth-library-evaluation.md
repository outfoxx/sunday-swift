# OAuth library evaluation across runtimes

Status: library-backed adapters implemented and exercised locally. Platform-matrix and hosted CI verification remain outstanding. Library selection includes all four runtimes and the Auth0/OAuthKit alternatives requested during implementation.

## Revised adoption criteria

Prefer maintained OAuth/OIDC libraries for protocol requests, response processing, discovery, PKCE, and error handling. Keep Sunday's existing public provider API and credential cache. A replaceable HTTP client is preferred, not mandatory; a library-owned isolated client is acceptable if cancellation, redirect handling, and credential isolation remain correct. Custom wire models are a fallback, not the default. Small, explicitly documented policy checks may surround library calls.

Evaluate the actual version against the shared fixture contract and managed Keycloak tests. Separate protocol requirements, Sunday restrictions, context-dependent policy, and provider compatibility. A library accepting a response that Sunday rejects is not automatically a library defect: some checks occur later, or require configured scopes and issuer context. Do not use raw mismatch counts as correctness scores.

## Candidates checked on 2026-10-05

| Runtime | Primary candidate | Alternatives | Important integration finding |
|---|---|---|---|
| Kotlin/JVM | Nimbus OAuth SDK 11.38.2 | Auth0 Java 5.4.0; framework OAuth clients if necessary | Nimbus request construction already runs through JDK and OkHttp; response normalization requires explicit handling. |
| JavaScript | oauth4webapi 3.8.8 | openid-client 6.8.8; Auth0 SPA 2.28.2 and auth0-auth-js 1.16.1 | oauth4webapi provides Fetch-based protocol functions and custom fetch injection, supports browser/Bun/Node, and avoids imposing application sessions. openid-client builds on oauth4webapi and adds JOSE. Node Auth0 7.3.0 directs authentication users to auth0-auth-js. |
| Python | Authlib 1.8.0 | OAuthLib 4.0.0; Auth0 Python 6.7.0; Auth0 Server Python 1.0.0b18 | Authlib 1.8 switched its async integration from HTTPX to HTTPX2. Evaluate its protocol layer or a dedicated client; don't silently upgrade Sunday's borrowed HTTPX client contract. |
| Swift / Apple | AppAuthCore 3.0.0; OAuthKit 2.2.0 under review | Auth0.swift 3.1.0; OAuthSwift 2.2.0; p2/OAuth2 5.2.0 | AppAuthCore is separately consumable and produces URLRequests, but its session override is global. OAuthKit supports per-instance URLSession injection and explicit provider endpoints; refresh behavior needs particular scrutiny. |

Licenses: Nimbus and AppAuth Apache-2.0; oauth4webapi/openid-client MIT; Authlib/OAuthLib BSD-3-Clause. Verify the final resolved graph and packaged footprint when selecting each dependency.

OAuthSwift's latest published release observed was May 2021, and p2/OAuth2's February 2020. This is a maintenance signal, not proof the repositories are abandoned. Prefer evaluating AppAuthCore first.

## Auth0 SDK configuration is not uniformly generic OAuth configuration

Auth0 custom-domain documentation describes an alternate hostname for an Auth0 tenant. It does not establish compatibility with arbitrary providers.

The inspected pinned Auth0 SDKs construct provider-specific paths:

- Auth0.swift 3.1.0 `Auth0Authentication` resolves `oauth/token` relative to its configured URL.
- Auth0 Java 5.4.0 `AuthAPI.getTokenUrl()` appends `oauth` and `token`; `withHttpClient` is available.
- Auth0 Python 6.7.0 `GetToken` constructs `{protocol}://{domain}/oauth/token`.
- Auth0 SPA 2.28.2 constructs `/authorize` and `/oauth/token` beneath its configured domain.

Keycloak advertises `/realms/{realm}/protocol/openid-connect/auth` and `/realms/{realm}/protocol/openid-connect/token`. A custom host alone cannot express these endpoint layouts. Rewriting URLs in an HTTP adapter could be technically possible but is not equivalent to supported generic-provider configuration; it must not be assumed safe or maintainable.

Auth0 Server Python 1.0.0b18 is different: its source uses Authlib, discovery metadata, and a resolved `token_endpoint`. Keep it in the comparison, but examine the additional cookie/session/Auth0 behavior and its beta status. Using its underlying generic library may be a smaller fit for Sunday's limited scope.

The newer `@auth0/auth0-auth-js` 1.16.1 is another important exception. Node Auth0 7 no longer exports the authentication client from its main entrypoint and directs users to this package. It is MIT-licensed and depends on `openid-client` and `jose`. Its discovery and token operations use discovered endpoints and support `customFetch`.

A passing isolated Bun probe (`.oauth-evaluation/js/auth0-probe.mjs`) configured a realm path in `domain` and supplied Keycloak-shaped discovery through a synthetic fetch implementation. Client-credentials exchange and refresh both reached the advertised Keycloak token URL using client-secret POST. This demonstrates generic endpoint mechanics, not documented support or live Keycloak interoperability. The same probe confirms public-client authorization fails with `MissingClientAuthError`. The inspected client-auth selection exposes POST, private-key JWT, and mTLS, but no Basic selection; it also forces HTTPS for discovery and does not apply per-request cancellation options to cold discovery. These are material mismatches with Sunday's public PKCE, confidential Basic, loopback testing, and cancellation requirements. Evaluate the underlying `openid-client` directly rather than reproducing Auth0-specific behavior or relying on URL rewriting.

No live Auth0 tenant was used for this evaluation. Documentation-backed Auth0 compatibility and successful live Auth0 interoperability must be reported separately.

## Executed probes

Isolated probes are under `.oauth-evaluation/` (not a production dependency change).

- oauth4webapi 3.8.8: 75 discovery/token fixture probes. Its discovery processing verifies issuer/object structure, with many metadata field checks deferred to usage. Token processing rejects several bad types but accepts numeric-string expiry (normalizes to a number), fractional/zero expiry, and scopes needing application-policy checks.
- Authlib 1.8.0: 75 discovery/token probes. `OAuth2Client.parse_response_token` does not provide the complete strict token wire contract. Full metadata validation also rejects some deliberately minimal Sunday discovery fixtures because they lack other required metadata. That distinction needs to be documented rather than worked around by changing expected outcomes blindly.
- OAuthLib 4.0.0: 44 token probes. Numeric strings and fractional expiry are normalized; null/wrong-type fields are not uniformly rejected. It is transport-independent but supplies less discovery functionality than Authlib.
- AppAuthCore 3.0.0: compiled and ran 44 token-model probes on macOS. Its model initializer can omit wrong-type/null properties instead of failing, and accepts fractional expiry. Service-level validation must be evaluated separately before deciding the adapter boundary.
- Nimbus 11.38.2: see `oauth-nimbus-evaluation.md`; assertions now distinguish null refresh/scope keys retained by serialization from a null discovery method list removed by normalization. Core, JDK, and OkHttp checks pass.

These observations support library-backed adapters with targeted checks. They do not justify immediately retaining complete custom implementations in every runtime.

## Implemented adoption boundaries

| Runtime | Adopted library | Boundary and evidence |
|---|---|---|
| Kotlin | Nimbus 11.38.2 | Protocol grant/authentication request construction; Sunday JDK/OkHttp execution. Strict response decoding remains internal because the evaluated parsers normalize wire distinctions and would require the same checks before parsing. See the dedicated report. |
| JavaScript | oauth4webapi 3.8.8 | Generic token endpoint requests, Basic/POST/None authentication, and token-success processing. Strict raw-number/scope checks precede library processing, with scope inclusion and absolute expiry checks after it. Discovery trust and error categorization remain Sunday policy. |
| Python | Authlib 1.8.0 | `prepare_token_request` and `ClientAuth` construct protocol requests; borrowed HTTPX executes them. Authlib's response parser adds no strict validation over the existing small wire checks, so those remain. Authlib Basic credentials need explicit RFC 6749 form encoding before its HTTP Basic encoding. No HTTPX2 integration or library credential lifecycle is used. |
| Swift | AppAuthCore 3.0.0 | `OIDTokenRequest` builds URLRequests for public, Basic, and POST clients; Sunday executes them using its isolated URLSession. POST secrets use additional body parameters, while Basic uses AppAuth's credential encoder. Normalizing response models would require duplicate strict validation, so response decoding remains internal. No global session override, browser UI, or credential persistence is adopted. |

The policy wrappers are private. No library types enter Sunday's public APIs. JavaScript passes only the OAuth fields consumed by this API to response processing: ID-token validation is outside scope, and passing `id_token` through would activate OIDC claim validation. Python's Authlib dependency is limited to the HTTPX/all extras. AppAuthCore adds no package dependencies; Authlib additionally resolves cryptography, joserfc, cffi and pycparser in the local locked graph. oauth4webapi has no runtime dependencies. Final packaged size remains to be measured.

Local verification after integration:

- JavaScript: lint, typecheck, build, all 701 tests, replay three authentication methods, and live Keycloak acquisition/refresh for all three.
- Python: lint, mypy, full 331-test suite at 92.31% coverage, replay, and live Keycloak for all three methods. Lifecycle failure tests pass, covering readiness timeout, Docker cleanup failure, and zero Docker calls during macOS CI startup failure.
- Swift: compiler, lint, full suite, replay and live Keycloak with public PKCE and confidential Basic/POST.
- Kotlin: core/JDK/OkHttp check tasks pass; Nimbus request integration previously passed managed replay/live through both transports.

These live checks used macOS CI selection (official Keycloak Java distribution). Python also passed container-backend acquisition/refresh after Authlib adoption. Repeat platform checks in CI. A sanitized Auth0-shaped refresh fixture is included; no live Auth0 tenant was configured and no live Auth0 compatibility is claimed.

## Remaining rollout verification

1. Exercise the existing platform matrices with the new dependencies and publish linked review PRs.
2. Expand matching fixtures to cover any remaining contextual/lifecycle gaps, including documented Auth0 shapes and consistent error categories, beyond parser acceptance.
3. Complete infrastructure fault coverage in each native harness and measure final resolved dependency/artifact footprint.
4. Keep replay for PRs and live integration on main through standard test entry points. Do not publish betas as part of this change.

## OAuthKit 2.2.0 initial review

Added at the user's suggestion. The tagged package (commit prefix `03a594b`) is MIT-licensed, uses Swift tools 6.1, and declares iOS 17, macOS 15, tvOS 18, and watchOS 10 minimums. These fit Sunday's currently declared Swift 6.2 / iOS 18 / macOS 15 / tvOS 18 / watchOS 11 baseline. Its documentation describes configurable authorization/token URLs, PKCE, client credentials, and a per-instance custom URLSession. These make it a relevant generic-provider candidate. The package declares swift-crypto for Linux/Android only.

The pinned source also exposes integration concerns that must be settled before adoption:

- `OAuth.Request.refresh` constructs a POST to `provider.authorizationURL`, putting refresh parameters in the URL query and leaving the body empty. The refresh parameter builder adds neither client-secret POST nor Basic authentication. `OAuth.refreshToken` calls this builder. This is inconsistent with the token-endpoint form POST needed for our Keycloak/Auth0 acceptance flows; this finding is source inspection, not a live test result.
- No discovery implementation or configurable Basic authentication was found in the inspected source. Explicit endpoint configuration is supported, but discovery/trust would still need an adapter or upstream additions.
- The main API owns observable authorization state, Keychain storage, and automatic refresh (which can be disabled). Its request builder is internal. Evaluate whether the existing Sunday callback and credential lifecycle can be preserved without duplicating that machinery.

Status: documentation/source review only; no OAuthKit compilation, fixture, or live-provider success is claimed. Next checks are a minimal consumer build, URLSession-captured code/refresh requests, parser fixtures, and managed replay/live tests if the endpoint/authentication issues can be addressed through supported APIs. Do not change platform minimums or adopt a fork implicitly.

## Primary sources

- [oauth4webapi](https://github.com/panva/oauth4webapi/tree/v3.8.8)
- [openid-client custom fetch](https://github.com/panva/openid-client/blob/main/docs/variables/customFetch.md)
- [Authlib 1.8 changes](https://docs.authlib.org/en/stable/upgrades/changelog.html)
- [Authlib HTTP clients](https://docs.authlib.org/en/stable/oauth2/client/http/index.html)
- [OAuthLib client API](https://oauthlib.readthedocs.io/en/latest/oauth2/clients/baseclient.html)
- [AppAuthCore package](https://github.com/openid/AppAuth-iOS/blob/3.0.0/Package.swift)
- [AppAuth session injection](https://github.com/openid/AppAuth-iOS/blob/3.0.0/Sources/AppAuthCore/OIDURLSessionProvider.h)
- [OAuthKit 2.2.0 manifest](https://github.com/codefiesta/OAuthKit/blob/2.2.0/Package.swift)
- [OAuthKit configuration](https://github.com/codefiesta/OAuthKit/blob/2.2.0/Sources/OAuthKit/OAuthKit.docc/Configuration.md)
- [OAuthKit request construction](https://github.com/codefiesta/OAuthKit/blob/2.2.0/Sources/OAuthKit/OAuth%2BRequest.swift)
- [Auth0 custom domains](https://auth0.com/docs/customize/custom-domains/configure-features-to-use-custom-domains)
- [Auth0.swift endpoint construction](https://github.com/auth0/Auth0.swift/blob/3.1.0/Auth0/Auth0Authentication.swift)
- [Auth0 Java client](https://github.com/auth0/auth0-java/blob/5.4.0/src/main/java/com/auth0/client/auth/AuthAPI.java)
- [Auth0 Python token client](https://github.com/auth0/auth0-python/blob/6.7.0/src/auth0/authentication/get_token.py)
- [Auth0 SPA token client](https://github.com/auth0/auth0-spa-js/blob/v2.28.2/src/api.ts)
- [Auth0 Server Python](https://github.com/auth0/auth0-server-python/tree/1.0.0b18)
- [Node Auth0 authentication migration](https://auth0.github.io/node-auth0/)
- [Auth0 Auth JS documentation](https://github.com/auth0/auth0-auth-js/tree/main/packages/auth0-auth-js)
- [Pinned Auth0 Auth JS 1.16.1 package](https://www.npmjs.com/package/@auth0/auth0-auth-js/v/1.16.1)
- [Keycloak endpoints](https://www.keycloak.org/securing-apps/oidc-layers)
- [Auth0's Authlib quickstart](https://auth0.com/docs/quickstart/webapp/django)

## Protocol and compatibility contract

- RFC 8414 sections 2 and 3.3 and OIDC Discovery section 4.3 define metadata and exact issuer checking. Sunday validates supplied endpoint types before applying overrides and validates resolved endpoints before calling application authorization. Refresh repeats discovery validation.
- RFC 6749 sections 5.1 and 5.2 define success/error responses. Successful discovery and token responses require HTTP 200. Sunday classifies transport failures, 408, 429, and 5xx as temporary without including provider response text in errors.
- RFC 6749 sections 2.3.1 and 3.3 define client authentication and scope syntax. Confidential clients use advertised methods, with absent metadata defaulting to Basic. Issue #59's public authorization-code exception allows missing `none`, an absent method list, or an empty list; this is a compatibility policy.
- RFC 6749 section 7.1 makes token types case-insensitive. Sunday supports Bearer, requires nonempty token strings, and requires returned scopes to contain requested scopes when supplied. Unknown extensions are ignored.
- Positive integral number lifetimes and the absolute safe-integer millisecond bound (9007199254740991) are Sunday restrictions for aligned expiry computation. Absent expiry stays unspecified. Explicit nulls and coercible strings are rejected.
- RFC 7636 sections 4.1 and 4.2 define PKCE verifier syntax and S256. The application owns browser authorization/state validation; runtime grants are consumed once. The managed test browser uses a fresh state and synthetic credentials.
- HTTPS is required except for Sunday's existing loopback HTTP allowance. Redirects and ambient transport credentials remain disabled. Refresh retains an omitted refresh token and replaces a rotated one through the existing credential manager.

## Running interoperability tests

`SUNDAY_OAUTH_TEST_MODE=replay` is the default. Select `live` for real Keycloak. Invalid values fail. Kotlin additionally accepts `-PoauthTestMode=live`, which takes precedence over the environment. Use each repository's standard Gradle, Swift, pytest, or Bun test entry point; test infrastructure provisions and tears down providers.

Replay uses checksum-pinned WireMock 3.13.1 as a Java process. Live uses Keycloak 26.2.5 pinned by checksum (Java distribution) or image digest (container). On macOS with CI enabled, backend selection chooses Java without Docker discovery. Empty/unset, `0`, and case-insensitive `false` disable CI detection. Other nonempty values enable it. Both backends import disposable realms with identical clients, users, callbacks, PKCE, and refresh rotation settings. Cached artifacts are verified before use; infrastructure failures never switch to replay. Provider/browser dependencies are test-only, and tests never rewrite fixtures.
