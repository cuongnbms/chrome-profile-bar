#!/bin/bash
# The Command Line Tools toolchain does not find the swift-testing macro plugin on its own.
set -euo pipefail
cd "$(dirname "$0")/.."
swift test -Xswiftc -plugin-path -Xswiftc "$(xcode-select -p)/usr/lib/swift/host/plugins/testing" "$@"
