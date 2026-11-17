#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
work=$(mktemp -d "${TMPDIR:-/tmp}/relaypad-protocol.XXXXXX")
trap 'rm -rf "$work"' EXIT
xcrun swiftc Shared/RemoteProtocol.swift Shared/SecureChannel.swift checks/ProtocolV1Tests.swift -o "$work/check"
"$work/check"
