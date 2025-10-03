# Polyglot Benchmarks Kit

Reproducible scripts to generate the metrics for Section 8 (Comparison Benchmarks) of your Quarto doc.

## Environment Variables (set these before running)

### Common
- `AZURE_TENANT_ID` – your Entra tenant GUID
- `AZURE_SQL_SERVER` – e.g., `your-server.database.windows.net`
- `AZURE_DATABASE` – target DB name

### Databricks
- `DATABRICKS_HOST` – e.g., `adb-1234567890123456.12.azuredatabricks.net`
- `DATABRICKS_TOKEN` – Personal Access Token with read perms
- `DATABRICKS_WAREHOUSE_HTTP_PATH` – SQL Warehouse HTTP path (for SQL/ODBC)
- Optionally, `DATABRICKS_CONFIG_PROFILE` – if using a named CLI profile

## Python
- `python/benchmark_sql_odbc.py` – Azure SQL via ODBC (pyodbc + Device Code / CLI)
- `python/benchmark_databricks_connect.py` – Databricks Connect v2 Spark query

## R
- `r/benchmark_sql_odbc.R` – Azure SQL via ODBC with `Authentication=ActiveDirectoryDeviceCode`
- `r/benchmark_sparklyr.R` – Databricks via `sparklyr`

## Rust
- `rust/Cargo.toml`
- `rust/src/bin/benchmark_polars.rs` – local Arrow/Parquet + Polars microbenchmarks (drop-in)
  > For remote sources, adapt to Arrow Flight SQL or local files staged from Databricks.

## Suggested workflow
1. Ensure drivers are present (ODBC Driver 18) and driver registered (`odbcinst -q -d`).
2. `python python/benchmark_sql_odbc.py`
3. `Rscript r/benchmark_sql_odbc.R`
4. `python python/benchmark_databricks_connect.py`
5. `Rscript r/benchmark_sparklyr.R`
6. `cd rust && cargo run --bin benchmark_polars --release`

Each script prints a small JSON summary you can paste into your Quarto tables.
