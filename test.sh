#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
mkdir -p "$ROOT/.build/cache"
xcrun swiftc -swift-version 5 -module-cache-path "$ROOT/.build/cache" -parse-as-library "$ROOT/Sources/Core.swift" "$ROOT/Tests/Tests.swift" -o "$ROOT/.build/tests"
if [ "${1:-}" = "--integration" ]; then
    READY="$(mktemp -d)"
    python3 "$ROOT/Tests/server.py" > "$READY/urls" 2> "$READY/errors" &
    SERVER_PID=$!
    trap 'kill "$SERVER_PID" 2>/dev/null || true; wait "$SERVER_PID" 2>/dev/null || true; rm -rf "$READY"' EXIT
    for attempt in {1..100}; do
        if [ -s "$READY/urls" ]; then break; fi
        if ! kill -0 "$SERVER_PID" 2>/dev/null; then cat "$READY/errors"; exit 1; fi
        sleep 0.1
    done
    read -r HTTP_URL TLS_URL < "$READY/urls"
    "$ROOT/.build/tests" "$HTTP_URL" "$TLS_URL"
else
    "$ROOT/.build/tests" "$@"
fi
