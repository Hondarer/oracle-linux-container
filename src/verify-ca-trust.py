#!/usr/bin/env python3
"""Check default OS/Python/Node/Java/NSS TLS stores without network access."""
import hashlib
import ensurepip
from pathlib import Path
import ssl
import subprocess
import sys
import tempfile
import base64
import json
from ca_distrust import BLOCKED, POLICY, dotnet_bundles, fingerprints, pem_certificates



def check(label, certificates):
    fingerprints = {hashlib.sha256(cert).hexdigest() for cert in certificates}
    if not fingerprints:
        raise RuntimeError(f"{label}: no CA certificates found")
    if fingerprints & BLOCKED:
        raise RuntimeError(f"{label}: distrusted root still trusted: {fingerprints & BLOCKED}")
    print(f"{label}: {len(fingerprints)} CA certificates, affected roots absent")


check("OS/Python ssl", ssl.create_default_context().get_ca_certs(binary_form=True))

import certifi
from pip._vendor import certifi as pip_certifi
from pip._vendor.packaging.version import Version
import pip

if Version(pip.__version__) < Version("26.2.2"):
    raise RuntimeError(f"pip {pip.__version__}: upgrade to 26.2.2 or later")
if Version(ensurepip.version()) < Version("26.2.2"):
    raise RuntimeError(f"ensurepip {ensurepip.version()}: new venvs would use unpatched pip")
for label, module in (("certifi", certifi), ("pip vendored certifi", pip_certifi)):
    if Version(module.__version__) < Version("2026.10.19"):
        raise RuntimeError(f"{label} {module.__version__}: upgrade required")
    check(label, pem_certificates(Path(module.where()).read_text()))

# Prove that an ordinary, offline venv creation uses the fixed wheel as well.
with tempfile.TemporaryDirectory(prefix="ca-trust-venv-") as directory:
    subprocess.run([sys.executable, "-m", "venv", directory], check=True)
    subprocess.run([str(Path(directory) / "bin/python"), "-c", """
import pip
from pip._vendor import certifi
from pip._vendor.packaging.version import Version
assert Version(pip.__version__) >= Version('26.2.2'), pip.__version__
assert Version(certifi.__version__) >= Version('2026.10.19'), certifi.__version__
print('new venv: pip ' + pip.__version__ + ', certifi ' + certifi.__version__)
"""], check=True)

# --use-openssl-ca delegates to the OS store checked above. In this mode Node's
# default CA enumeration is empty; --use-system-ca would also trust bundled CAs.
subprocess.run(["node", "-e", r"""
const tls = require('node:tls');
if (!(process.env.NODE_OPTIONS || '').split(/\s+/).includes('--use-openssl-ca') ||
    tls.getCACertificates('default').length !== 0) {
  throw new Error('Node.js must use the updated OpenSSL CA store exclusively');
}
console.log('Node.js ' + process.versions.node + ': OS CA store selected');
"""], check=True)

# Official Node.js builds, including the one GitHub Actions brings into job
# containers, use OPENSSLDIR=/etc/ssl and read /etc/ssl/cert.pem in this mode.
check("/etc/ssl/cert.pem", pem_certificates(Path("/etc/ssl/cert.pem").read_text()))

java_certs = subprocess.run(
    ["keytool", "-list", "-rfc", "-cacerts", "-storepass", "changeit"],
    check=True, capture_output=True, text=True)
check("Java cacerts", pem_certificates(java_certs.stdout))

nss_module = Path("/usr/lib64/libnssckbi.so").resolve(strict=True)
if nss_module.name != "p11-kit-trust.so":
    raise RuntimeError(f"NSS uses an independent trust store: {nss_module}")
print(f"NSS: OS trust via {nss_module}")

for bundle in dotnet_bundles():
    check(str(bundle), pem_certificates(bundle.read_text()))
policy_certs = [base64.b64decode(cert, validate=True) for cert in
                json.loads(POLICY.read_text())["CADistrustedCertificates"]]
if len(policy_certs) != len(BLOCKED) or fingerprints(policy_certs) != BLOCKED:
    raise RuntimeError("Chrome distrust policy does not cover the expected root keys")
print("Chrome managed distrust policy: expected root keys configured")
