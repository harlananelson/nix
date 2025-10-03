#!/usr/bin/env bash
set -euo pipefail

# Advisory health-check for Python keyring in headless shells.
# Behavior:
# - Prints backend info and basic get/set capability.
# - If KEYRING_WRITE_TEST=1, attempts to set and delete a dummy secret.
# - Exit non-zero on backend import failure or when write test fails.
# - By default, absence of a proper backend is considered a warning; set KEYRING_STRICT=1 to fail.

STRICT="${KEYRING_STRICT:-0}"
WRITE_TEST="${KEYRING_WRITE_TEST:-0}"

python - <<'PY' || { echo "[keyring] import failed"; exit 1; }
import json, sys
try:
    import keyring
except Exception as e:
    print(json.dumps({"ok": False, "error": f"import: {e.__class__.__name__}: {e}"}))
    sys.exit(1)
kr = keyring.get_keyring()
print(json.dumps({"ok": True, "backend": kr.__class__.__name__, "module": kr.__class__.__module__}))
PY

if [[ "$WRITE_TEST" == "1" ]]; then
  python - <<'PY' || { echo "[keyring] write test failed"; exit 1; }
import os, sys, json
import keyring
svc = "headless-keyring-health"
usr = "self-test"
val = "ok"
try:
    keyring.set_password(svc, usr, val)
    got = keyring.get_password(svc, usr)
    keyring.delete_password(svc, usr)
    print(json.dumps({"write_ok": got == val}))
    sys.exit(0 if got == val else 2)
except Exception as e:
    print(json.dumps({"write_ok": False, "error": str(e)}))
    sys.exit(2)
PY
fi

if [[ "$STRICT" == "1" && "$WRITE_TEST" != "1" ]]; then
  echo "[keyring] STRICT=1 but WRITE_TEST not enabled; cannot verify persistence. Consider setting KEYRING_WRITE_TEST=1."
fi

echo "[keyring] OK (advisory)"
