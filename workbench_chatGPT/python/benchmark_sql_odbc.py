#!/usr/bin/env python3

import os, time, json, struct, sys
import pyodbc

from azure.identity import DefaultAzureCredential, DeviceCodeCredential, AzureCliCredential

SERVER = os.getenv("AZURE_SQL_SERVER")
DATABASE = os.getenv("AZURE_DATABASE")
TENANT = os.getenv("AZURE_TENANT_ID")
SCOPE = "https://database.windows.net/.default"

QUERY = os.getenv("BENCH_QUERY", "SELECT TOP 1000000 * FROM sys.objects a CROSS JOIN sys.objects b")

def _wide_token(token: str) -> bytes:
    w = token.encode("utf-16-le")
    return struct.pack("=i", len(w)) + w

def get_token():
    # Try Default (excluding interactive browser), then CLI, then Device Code
    try:
        cred = DefaultAzureCredential(exclude_interactive_browser_credential=True)
        return cred.get_token(SCOPE).token
    except Exception:
        pass
    try:
        return AzureCliCredential().get_token(SCOPE).token
    except Exception:
        pass
    return DeviceCodeCredential(tenant_id=TENANT).get_token(SCOPE).token

def main():
    if not SERVER or not DATABASE or not TENANT:
        print("Missing env: AZURE_SQL_SERVER / AZURE_DATABASE / AZURE_TENANT_ID", file=sys.stderr)
        sys.exit(2)

    token = get_token()
    conn_str = (
        f"Driver={{ODBC Driver 18 for SQL Server}};"
        f"Server={SERVER};Database={DATABASE};Encrypt=yes;TrustServerCertificate=no;"
    )

    t0 = time.perf_counter()
    conn = pyodbc.connect(conn_str, attrs_before={1256: _wide_token(token)})
    t_connect = (time.perf_counter() - t0) * 1000.0

    cur = conn.cursor()
    t1 = time.perf_counter()
    rows = cur.execute(QUERY).fetchall()
    t_query = (time.perf_counter() - t1)

    # Minimal metrics
    result = {
        "engine": "azure-sql-odbc",
        "connect_ms": round(t_connect, 2),
        "query_s": round(t_query, 3),
        "rows_returned": len(rows),
        "query_sample": QUERY[:120] + ("..." if len(QUERY) > 120 else ""),
    }
    print(json.dumps(result, indent=2))

if __name__ == "__main__":
    main()
