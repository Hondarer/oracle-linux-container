#!/bin/bash
# Positive control for the filtered SDK timestamp/code-signing trust bundles.
set -euo pipefail
signature_probe_dir="$(mktemp -d /tmp/nuget-signature.XXXXXX)"
trap 'rm -rf "$signature_probe_dir"' EXIT
curl --fail --location --show-error --connect-timeout 30 --max-time 180 \
    https://api.nuget.org/v3-flatcontainer/newtonsoft.json/13.0.3/newtonsoft.json.13.0.3.nupkg \
    -o "$signature_probe_dir/newtonsoft.json.13.0.3.nupkg"
dotnet nuget verify --all "$signature_probe_dir/newtonsoft.json.13.0.3.nupkg"
