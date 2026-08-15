#!/usr/bin/env bash

set -euo pipefail

if [[ $# -lt 2 || $# -gt 3 ]]; then
    echo "Usage: $0 <version> <dmg-path> [output-path]" >&2
    exit 1
fi

version="${1#v}"
dmg="$2"
output="${3:-mactivate.rb}"

if [[ ! -f "$dmg" ]]; then
    echo "Disk image not found: $dmg" >&2
    exit 1
fi

if [[ ! "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+([-.][0-9A-Za-z.]+)?$ ]]; then
    echo "Version must be semantic, for example 1.0.0." >&2
    exit 1
fi

sha256="$(shasum -a 256 "$dmg" | awk '{ print $1 }')"
mkdir -p "$(dirname "$output")"

cat > "$output" <<EOF
cask "mactivate" do
  version "$version"
  sha256 "$sha256"

  url "https://github.com/HarshitBadam/mactivate/releases/download/v#{version}/Mactivate-#{version}.dmg"
  name "Mactivate"
  desc "Turn built-in sensors and physical gestures into system controls"
  homepage "https://github.com/HarshitBadam/mactivate"

  livecheck do
    url :url
    strategy :github_latest
  end

  depends_on arch: :arm64
  depends_on macos: :ventura

  app "Mactivate.app"

  caveats <<~EOS
    Mactivate is distributed without Apple notarization. On first launch,
    macOS may require approval in System Settings > Privacy & Security.
    Do not disable Gatekeeper.
  EOS
end
EOF

echo "Created $output"
