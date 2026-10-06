# Nimbus evaluation

Evaluated `com.nimbusds:oauth2-oidc-sdk:11.38.2` on the repository Java 21 baseline. Apache-2.0 license. `NimbusEvaluationTest` reproduces the response-parser observations; the native OAuth fixtures exercise request construction through JDK and OkHttp.

## Observed response parsing

| Input | Nimbus result | Sunday contract |
|---|---|---|
| Absent expiry | Preserved as unspecified | Accept |
| Null expiry | ParseException | Reject |
| Fractional expiry 1.5 | Truncated to 1 | Reject |
| String expiry "60" | Coerced to 60 | Reject |
| Null refresh token / scope | Accepted, null keys retained in serialized output | Reject |
| Null discovery auth-method list | Removed; indistinguishable from absence | Reject |
| Mixed string/number method list | ParseException | Reject |

Decision: retain strict internal discovery/token-success/token-error models. Nimbus response parsing would require validating substantially the same response a second time before parsing, and its normalized metadata loses distinctions needed for policy. Use Nimbus's grant and client-authentication request construction only. Never call Nimbus HTTP send or use Nimbus credential persistence; Sunday retains transport execution, cancellation, issuer policy, refresh lifecycle, and safe errors. No Nimbus types enter public signatures.

Resolved dependencies: Nimbus SDK 11.38.2, JOSE/JWT 10.9.1, content-type 2.3, lang-tag 1.7, json-smart/accessors-smart 2.6.0, ASM 9.7.1, jcip-annotations 1.0-1. No Jackson/Kotlin/coroutine dependency replacement was introduced by this graph. See the evaluation tests and native lifecycle tests before upgrading Nimbus.
