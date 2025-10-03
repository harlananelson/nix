#!/usr/bin/env bash
set -euo pipefail

: "${AZURE_SQL_SERVER:=}"
: "${AZURE_DATABASE:=}"
: "${AZURE_TENANT_ID:=}"

if [[ -z "${AZURE_SQL_SERVER}" || -z "${AZURE_DATABASE}" || -z "${AZURE_TENANT_ID}" ]]; then
  echo "[py-smoke] Skipping: set AZURE_SQL_SERVER, AZURE_DATABASE, AZURE_TENANT_ID to run."
  exit 0
fi

python - <<'PY'
import os, struct, pyodbc
from azure.identity import DefaultAzureCredential, AzureCliCredential, DeviceCodeCredential

scope = "https://database.windows.net/.default"
server = os.environ["AZURE_SQL_SERVER"]
db = os.environ["AZURE_DATABASE"]
tenant = os.environ["AZURE_TENANT_ID"]

# headless-safe fallback chain
token = None
try:
    token = DefaultAzureCredential(exclude_interactive_browser_credential=True).get_token(scope).token
except Exception:
    try:
        token = AzureCliCredential().get_token(scope).token
    except Exception:
        token = DeviceCodeCredential(tenant_id=tenant).get_token(scope).token

w = token.encode("utf-16-le")
access = struct.pack("=i", len(w)) + w

conn = pyodbc.connect(
    f"Driver={{ODBC Driver 18 for SQL Server}};Server={server};Database={db};Encrypt=yes;TrustServerCertificate=no;",
    attrs_before={1256: access}
)
val = conn.cursor().execute("SELECT 1").fetchone()[0]
print(f"[py-smoke] SELECT 1 -> {val}")
conn.close()
PY
