/*
 * Copyright 2021 Outfox, Inc.
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *    http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

import Foundation


/// Responsible for managing the mapping of `ServerTrustPolicy` objects to a given host.
open class ServerTrustPolicyManager {
  /// The dictionary of policies mapped to a particular host.
  public let policies: [String: ServerTrustPolicy]

  /// Initializes the `ServerTrustPolicyManager` instance with the given policies.
  ///
  /// Since different servers and web services can have different leaf certificates, intermediate and even root
  /// certficates, it is important to have the flexibility to specify evaluation policies on a per host basis. This
  /// allows for scenarios such as using default evaluation for host1, certificate pinning for host2, public key
  /// pinning for host3 and disabling evaluation for host4.
  ///
  /// - parameter policies: A dictionary of all policies mapped to a particular host.
  ///
  /// - returns: The new `ServerTrustPolicyManager` instance.
  public init(policies: [String: ServerTrustPolicy]) {
    self.policies = policies
  }

  /// Returns the `ServerTrustPolicy` for the given host if applicable.
  ///
  /// By default, this method will return the policy that perfectly matches the given host. Subclasses could override
  /// this method and implement more complex mapping implementations such as wildcards.
  ///
  /// - parameter host: The host to use when searching for a matching policy.
  ///
  /// - returns: The server trust policy for the given host if found.
  open func serverTrustPolicy(forHost host: String) -> ServerTrustPolicy? {
    return policies[host]
  }
}

// MARK: -


// MARK: - ServerTrustPolicy

/// The `ServerTrustPolicy` evaluates the server trust generally provided by an `NSURLAuthenticationChallenge` when
/// connecting to a server over a secure HTTPS connection. The policy configuration then evaluates the server trust
/// with a given set of criteria to determine whether the server trust is valid and the connection should be made.
///
/// Using pinned certificates or public keys for evaluation helps prevent man-in-the-middle (MITM) attacks and other
/// vulnerabilities. Applications dealing with sensitive customer data or financial information are strongly encouraged
/// to route all communication over an HTTPS connection with pinning enabled.
///
/// - performDefaultEvaluation: Uses the default server trust evaluation while allowing you to control whether to
///                             validate the host provided by the challenge. Applications are encouraged to always
///                             validate the host in production environments to guarantee the validity of the server's
///                             certificate chain.
///
/// - performRevokedEvaluation: Uses the default and revoked server trust evaluations allowing you to control whether to
///                             validate the host provided by the challenge as well as specify the revocation flags for
///                             testing for revoked certificates. Apple platforms did not start testing for revoked
///                             certificates automatically until iOS 10.1, macOS 10.12 and tvOS 10.1 which is
///                             demonstrated in our TLS tests. Applications are encouraged to always validate the host
///                             in production environments to guarantee the validity of the server's certificate chain.
///
/// - pinCertificates:          Uses the pinned certificates to validate the server trust. The server trust is
///                             considered valid if one of the pinned certificates match one of the server certificates.
///                             By validating both the certificate chain and host, certificate pinning provides a very
///                             secure form of server trust validation mitigating most, if not all, MITM attacks.
///                             Applications are encouraged to always validate the host and require a valid certificate
///                             chain in production environments.
///
/// - pinPublicKeys:            Uses the pinned public keys to validate the server trust. The server trust is considered
///                             valid if one of the pinned public keys match one of the server certificate public keys.
///                             By validating both the certificate chain and host, public key pinning provides a very
///                             secure form of server trust validation mitigating most, if not all, MITM attacks.
///                             Applications are encouraged to always validate the host and require a valid certificate
///                             chain in production environments.
///
/// - disableEvaluation:        Disables all evaluation which in turn will always consider any server trust as valid.
///
/// - customEvaluation:         Uses the associated closure to evaluate the validity of the server trust.
public enum ServerTrustPolicy {
  case performDefaultEvaluation(validateHost: Bool)
  case performRevokedEvaluation(validateHost: Bool, revocationFlags: CFOptionFlags)
  case pinCertificates(certificates: [SecCertificate], validateCertificateChain: Bool, validateHost: Bool)
  case pinPublicKeys(publicKeys: [SecKey], validateCertificateChain: Bool, validateHost: Bool)
  case disableEvaluation
  case customEvaluation((_ serverTrust: SecTrust, _ host: String) -> Bool)

  // MARK: - Bundle Location

  /// Returns all certificates within the given bundle with a `.cer`, `.CER`, `.crt`, `.CRT`, `.der`, or `.DER`
  /// file extensions.
  ///
  /// - parameter bundle: The bundle to search for all `.cer` files.
  ///
  /// - returns: All certificates within the given bundle.
  public static func certificates(in bundle: Bundle = Bundle.main) -> [SecCertificate] {
    var certificates: [SecCertificate] = []

    let paths = Set([".cer", ".CER", ".crt", ".CRT", ".der", ".DER"].map { fileExtension in
      bundle.paths(forResourcesOfType: fileExtension, inDirectory: nil)
    }.joined())

    for path in paths {
      if
        let certificateData = try? Data(contentsOf: URL(fileURLWithPath: path)) as CFData,
        let certificate = SecCertificateCreateWithData(nil, certificateData)
      {
        certificates.append(certificate)
      }
    }

    return certificates
  }

  /// Extracts and returns all public keys from certificates within the given bundle with a `.cer`, `.CER`, `.crt`,
  /// `.CRT`, `.der`, or `.DER` file extension.
  ///
  /// - parameter bundle: The bundle to search for all `*.cer` files.
  ///
  /// - returns: All public keys within the given bundle.
  public static func publicKeys(in bundle: Bundle = Bundle.main) -> [SecKey] {
    var publicKeys: [SecKey] = []

    for certificate in certificates(in: bundle) {
      if let publicKey = publicKey(for: certificate) {
        publicKeys.append(publicKey)
      }
    }

    return publicKeys
  }

  // MARK: - Evaluation

  /// Evaluates whether the server trust is valid for the given host.
  ///
  /// - parameter serverTrust: The server trust to evaluate.
  /// - parameter host:        The host of the challenge protection space.
  ///
  /// - returns: Whether the server trust is valid.
  public func evaluate(_ serverTrust: SecTrust, forHost host: String) -> Bool {
    var serverTrustIsValid = false

    switch self {
    case .performDefaultEvaluation(let validateHost):

      let policy = SecPolicyCreateSSL(true, validateHost ? host as CFString : nil)
      SecTrustSetPolicies(serverTrust, policy)

      serverTrustIsValid = trustIsValid(serverTrust)

    case .performRevokedEvaluation(let validateHost, let revocationFlags):

      let defaultPolicy = SecPolicyCreateSSL(true, validateHost ? host as CFString : nil)
      let revokedPolicy = SecPolicyCreateRevocation(revocationFlags)
      SecTrustSetPolicies(serverTrust, [defaultPolicy, revokedPolicy] as CFTypeRef)

      serverTrustIsValid = trustIsValid(serverTrust)

    case .pinCertificates(let pinnedCertificates, let validateCertificateChain, let validateHost):

      if validateCertificateChain {
        let policy = SecPolicyCreateSSL(true, validateHost ? host as CFString : nil)
        SecTrustSetPolicies(serverTrust, policy)

        SecTrustSetAnchorCertificates(serverTrust, pinnedCertificates as CFArray)
        SecTrustSetAnchorCertificatesOnly(serverTrust, true)

        serverTrustIsValid = trustIsValid(serverTrust)
      }
      else {
        let serverCertificatesDataArray = certificateData(for: serverTrust)
        let pinnedCertificatesDataArray = certificateData(for: pinnedCertificates)

        outerLoop: for serverCertificateData in serverCertificatesDataArray {
          for pinnedCertificateData in pinnedCertificatesDataArray
            where serverCertificateData == pinnedCertificateData {

            serverTrustIsValid = true
            break outerLoop
          }
        }
      }

    case .pinPublicKeys(let pinnedPublicKeys, let validateCertificateChain, let validateHost):

      var certificateChainEvaluationPassed = true

      if validateCertificateChain {
        let policy = SecPolicyCreateSSL(true, validateHost ? host as CFString : nil)
        SecTrustSetPolicies(serverTrust, policy)

        certificateChainEvaluationPassed = trustIsValid(serverTrust)
      }

      if certificateChainEvaluationPassed {
        let comparableServerKeys = Set(Self.publicKeys(for: serverTrust).compactMap { Self.data(for: $0) })
        let comparablePinnedPublicKeys = Set(pinnedPublicKeys.compactMap { Self.data(for: $0) })
        serverTrustIsValid = !comparableServerKeys.isDisjoint(with: comparablePinnedPublicKeys)
      }

    case .disableEvaluation:
      serverTrustIsValid = true

    case .customEvaluation(let closure):
      serverTrustIsValid = closure(serverTrust, host)

    }

    return serverTrustIsValid
  }

  // MARK: - Private - Trust Validation

  private func trustIsValid(_ trust: SecTrust) -> Bool {
    var error: CFError?
    return SecTrustEvaluateWithError(trust, &error)
  }

  // MARK: - Private - Certificate Data

  private func certificateData(for trust: SecTrust) -> [Data] {
    return certificateData(for: Self.copyChain(from: trust))
  }

  private func certificateData(for certificates: [SecCertificate]) -> [Data] {
    return certificates.map { SecCertificateCopyData($0) as Data }
  }

  // MARK: - Private - Public Key Extraction

  private static func publicKeys(for trust: SecTrust) -> [SecKey] {

    return copyChain(from: trust).compactMap { publicKey(for: $0) }
  }

  private static func publicKey(for certificate: SecCertificate) -> SecKey? {
    return SecCertificateCopyKey(certificate)
  }

  private static func data(for key: SecKey) -> Data? {

    var error: Unmanaged<CFError>?
    defer { error?.release() }

    guard let data = SecKeyCopyExternalRepresentation(key, &error) else {
      return nil
    }

    return data as Data
  }

  private static func copyChain(from trust: SecTrust) -> [SecCertificate] {
    if #available(macOS 12.0, iOS 15.0, tvOS 15.0, watchOS 8.0, *) {

      guard let chain = SecTrustCopyCertificateChain(trust) as? [SecCertificate]  else {
        return []
      }

      return chain
    }
    else {

      var chain: [SecCertificate] = []

      for index in 0 ..< SecTrustGetCertificateCount(trust) {
        if let certificate = SecTrustGetCertificateAtIndex(trust, index) {
          chain.append(certificate)
        }
      }

      return chain
    }
  }

}
