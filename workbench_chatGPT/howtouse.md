Awesome — I built you a small, reproducible benchmark kit (Python, R, Rust) you can download and run.
	•	Download the benchmarks README
	•	Python:
	•	benchmark_sql_odbc.py
	•	benchmark_databricks_connect.py
	•	R:
	•	benchmark_sql_odbc.R
	•	benchmark_sparklyr.R
	•	Rust:
	•	Cargo.toml
	•	benchmark_polars.rs

How to use (quick)
	1.	Set environment variables (examples)

export AZURE_TENANT_ID="00000000-0000-0000-0000-000000000000"
export AZURE_SQL_SERVER="your-server.database.windows.net"
export AZURE_DATABASE="your_db"

export DATABRICKS_HOST="adb-1234567890123456.12.azuredatabricks.net"
export DATABRICKS_TOKEN="dapiXXXXX"
# optional if you benchmark SQL Warehouse via ODBC/JDBC
export DATABRICKS_WAREHOUSE_HTTP_PATH="/sql/1.0/warehouses/xxxx"

	2.	Run the scripts

# Azure SQL via ODBC (Python)
python /path/to/benchmark_sql_odbc.py

# Azure SQL via ODBC (R, headless-safe device code)
Rscript /path/to/benchmark_sql_odbc.R

# Databricks Connect v2 (Python)
python /path/to/benchmark_databricks_connect.py

# Databricks via sparklyr (R)
Rscript /path/to/benchmark_sparklyr.R

	3.	Rust/Polars microbench (local Arrow/Parquet or synthetic)

cd /path/to/rust
cargo run --bin benchmark_polars --release

Each script prints a compact JSON summary (connect latency, query time, rows), ready to paste into your Quarto Comparison Benchmarks tables.

If you want, I can also add:
	•	a tiny Makefile to run them all and append results to a CSV/JSON log, and
	•	a Quarto partial that loads the log and renders the tables automatically. ￼