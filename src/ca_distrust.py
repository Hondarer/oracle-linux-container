#!/usr/bin/env python3
"""Apply explicit eMudhra distrust to independent application trust stores."""
import base64
import hashlib
import json
from pathlib import Path
import re
import ssl

BLOCKED = {
    "86a1ecba089c4a8d3bbe2734c612ba341d813e043cf9e8a862cd5c57a36bbe6b",
    "d7a7a0fb5d7e2731d771e9484ebcdef71d5f0c3e0a2948782bc83ee0ea699ef4",
    "7dd78d5f4f13459a83dff9abbba62edbaf6f2d102bf257fd712f4d9f2746ed8d",
    "f2edaaff3d9b701fb4d14c9f285f8c0bad90fc3bcc1fa07d47f4718edaba34a5",
}
PEM_PATTERN = r"-----BEGIN CERTIFICATE-----.*?-----END CERTIFICATE-----"
ROOTS = Path("/usr/local/share/oracle-linux-dev-container/emudhra-roots.pem")
POLICY = Path("/etc/opt/chrome_for_testing/policies/managed/emudhra.json")


def pem_certificates(text):
    return [ssl.PEM_cert_to_DER_cert(pem) for pem in re.findall(PEM_PATTERN, text, re.S)]


def fingerprints(certificates):
    return {hashlib.sha256(cert).hexdigest() for cert in certificates}


def dotnet_bundles():
    paths = []
    for root in ("/usr/lib64/dotnet/sdk", "/usr/share/dotnet/sdk"):
        paths.extend(Path(root).glob("*/trustedroots/*.pem"))
    if not paths:
        raise RuntimeError("No .NET SDK trust bundles found")
    return sorted(paths)


def apply():
    certificates = pem_certificates(ROOTS.read_text())
    if len(certificates) != len(BLOCKED) or fingerprints(certificates) != BLOCKED:
        raise RuntimeError("Distrust certificate fixture SHA256 mismatch")
    POLICY.parent.mkdir(parents=True, exist_ok=True)
    POLICY.write_text(json.dumps({"CADistrustedCertificates": [
        base64.b64encode(cert).decode("ascii") for cert in certificates
    ]}, indent=2) + "\n")
    POLICY.chmod(0o644)
    print(f"Chrome managed distrust policy: {len(certificates)} root keys")

    for path in dotnet_bundles():
        text = path.read_text()
        before = pem_certificates(text)
        if not before:
            raise RuntimeError(f"Empty or unrecognized .NET trust bundle: {path}")

        def retain(match):
            cert = ssl.PEM_cert_to_DER_cert(match.group())
            return "" if fingerprints([cert]) & BLOCKED else match.group()

        cleaned = re.sub(PEM_PATTERN, retain, text, flags=re.S)
        after = pem_certificates(cleaned)
        if not after or fingerprints(after) & BLOCKED:
            raise RuntimeError(f"Failed to filter .NET trust bundle: {path}")
        if cleaned != text:
            path.write_text(cleaned)
        print(f"{path}: removed {len(before) - len(after)}, retained {len(after)} certificates")


if __name__ == "__main__":
    apply()
