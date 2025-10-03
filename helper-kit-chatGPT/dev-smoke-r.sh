#!/usr/bin/env bash
set -euo pipefail

: "${AZURE_SQL_SERVER:=}"
: "${AZURE_DATABASE:=}"

if [[ -z "${AZURE_SQL_SERVER}" || -z "${AZURE_DATABASE}" ]]; then
  echo "[r-smoke] Skipping: set AZURE_SQL_SERVER and AZURE_DATABASE to run."
  exit 0
fi

Rscript - <<'RS'
suppressMessages({ library(DBI); library(odbc) })
server <- Sys.getenv("AZURE_SQL_SERVER")
database <- Sys.getenv("AZURE_DATABASE")
con <- dbConnect(odbc::odbc(),
  Driver="ODBC Driver 18 for SQL Server",
  Server=server,
  Database=database,
  Encrypt="yes",
  TrustServerCertificate="no",
  Authentication="ActiveDirectoryDeviceCode"
)
val <- dbGetQuery(con, "SELECT 1 AS v")$v[1]
cat(sprintf("[r-smoke] SELECT 1 -> %s\n", as.character(val)))
dbDisconnect(con)
RS
