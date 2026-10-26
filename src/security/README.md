# eMudhra distrust fixtures

`emudhra-roots.pem` contains public CA certificates, not private keys. It was
retrieved from https://emudhra.we-have-a-problem.com/roots.json on 2026-10-26.
The four certificate SHA256 fingerprints are pinned in `../ca_distrust.py`.

The certificates are used to remove matching roots from .NET SDK trust bundles
and to configure Chrome's supported `CADistrustedCertificates` policy. Chrome
matches SPKI, covering certificates with the same key, including cross-signs.

Policy schema and Linux CFT policy directory:

- https://raw.githubusercontent.com/chromium/chromium/main/components/policy/resources/templates/policy_definitions/CertificateManagement/CADistrustedCertificates.yaml
- https://raw.githubusercontent.com/chromium/chromium/main/components/policy/core/common/policy_paths.cc
