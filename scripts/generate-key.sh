#!/usr/bin/env bash
set -euo pipefail

usage() {
    echo "Usage: $0" >&2
    echo "  Generates a fresh, throwaway secp256k1 keypair. Use the address for" >&2
    echo "  a TEE package's 'initial_owner' and the private key for tee-proxy's" >&2
    echo "  'tee_proxy_private_key' -- they are two halves of one keypair, not" >&2
    echo "  two independent secrets. Prints both to stdout only -- nothing is" >&2
    echo "  written to disk." >&2
    exit 1
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    usage
fi

# eth-keys cannot hash on its own: without a backend, to_checksum_address()
# raises "ImportError: None of these hashing backends are installed".
DEPS=(eth-keys 'eth-hash[pycryptodome]')

read -r -d '' PROGRAM <<'PY' || true
import secrets
from eth_keys import keys

private_key = secrets.token_bytes(32)
address = keys.PrivateKey(private_key).public_key.to_checksum_address()

print(f"address:     {address}")
print(f"private_key: 0x{private_key.hex()}")
PY

# Both paths below keep the dependencies out of the caller's site-packages.
if command -v uv >/dev/null 2>&1; then
    uv run --quiet --no-project \
        "${DEPS[@]/#/--with=}" \
        - <<<"$PROGRAM"
elif command -v python3 >/dev/null 2>&1; then
    venv=$(mktemp -d)
    trap 'rm -rf "$venv"' EXIT
    echo "Building a throwaway venv (install uv to skip this)..." >&2
    python3 -m venv "$venv"
    # Windows/Git Bash lays the venv out as Scripts/, POSIX as bin/.
    if [[ -x "$venv/bin/python" ]]; then
        venv_python="$venv/bin/python"
    else
        venv_python="$venv/Scripts/python.exe"
    fi
    "$venv_python" -m pip install --quiet --upgrade pip
    "$venv_python" -m pip install --quiet "${DEPS[@]}"
    "$venv_python" - <<<"$PROGRAM"
else
    echo "Need either uv or python3 on PATH; found neither." >&2
    exit 1
fi

echo >&2
echo "Not stored anywhere -- copy what you need now, this output will not be repeated." >&2
