#!/usr/bin/env bash
set -euo pipefail

usage() {
    echo "Usage: $0" >&2
    echo "  Generates a fresh, throwaway secp256k1 keypair. Use the address for" >&2
    echo "  a TEE package's 'initial_owner' and the private key for tee-proxy's" >&2
    echo "  'tee_proxy_private_key'. Prints both to stdout only -- nothing is" >&2
    echo "  written to disk." >&2
    exit 1
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    usage
fi

if ! command -v python3 >/dev/null 2>&1; then
    echo "python3 is required but was not found on PATH" >&2
    exit 1
fi

if ! python3 -c "import eth_keys" >/dev/null 2>&1; then
    echo "Installing eth-keys (one-time, needed to derive the address)..." >&2
    python3 -m pip install --quiet eth-keys
fi

python3 - <<'PY'
import secrets
from eth_keys import keys

private_key = secrets.token_bytes(32)
address = keys.PrivateKey(private_key).public_key.to_checksum_address()

print(f"address:     {address}")
print(f"private_key: 0x{private_key.hex()}")
PY

echo >&2
echo "Not stored anywhere -- copy what you need now, this output will not be repeated." >&2
