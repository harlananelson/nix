#!/usr/bin/env bash
set -euo pipefail

echo "[odbc-check] Checking ODBC driver registration"
: "${ODBCSYSINI:=$HOME/.odbc}"
: "${ODBCINI:=$HOME/.odbc/odbc.ini}"

if [[ ! -d "$ODBCSYSINI" ]]; then
  echo "[odbc-check] ODBCSYSINI dir missing: $ODBCSYSINI"
  exit 1
fi

ODBCINST="$ODBCSYSINI/odbcinst.ini"
if [[ ! -f "$ODBCINST" ]]; then
  echo "[odbc-check] Missing $ODBCINST"
  exit 1
fi

if ! odbcinst -q -d | grep -q "ODBC Driver 18 for SQL Server"; then
  echo "[odbc-check] 'ODBC Driver 18 for SQL Server' not listed by odbcinst"
  echo "[odbc-check] Contents of $ODBCINST:"
  sed -n '1,120p' "$ODBCINST"
  exit 1
fi

driver_path="$(awk -F= '/^\[ODBC Driver 18 for SQL Server\]/{flag=1;next} /^\[/{flag=0} flag && $1 ~ /^Driver/{gsub(/^[ \t]+|[ \t]+$/,"",$2); print $2}' "$ODBCINST" | head -n1)"
if [[ -z "$driver_path" ]]; then
  echo "[odbc-check] Could not parse Driver= line from $ODBCINST"
  exit 1
fi

# Resolve globs if present
shopt -s nullglob
matches=( $driver_path )
if [[ ${#matches[@]} -eq 0 ]]; then
  echo "[odbc-check] Driver path not found on disk: $driver_path"
  exit 1
fi

echo "[odbc-check] Driver registered and found: ${matches[0]}"
echo "[odbc-check] OK"
