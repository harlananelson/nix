#!/usr/bin/env python3
import os, time, json, sys
from databricks.connect import DatabricksSession

# Pre-req: DATABRICKS_HOST and DATABRICKS_TOKEN set (or auth profile configured)
QUERY = os.getenv("DBX_BENCH_QUERY", "SELECT current_catalog() AS cat, current_schema() AS sch")

def main():
    t0 = time.perf_counter()
    spark = DatabricksSession.builder.getOrCreate()
    t_connect = (time.perf_counter() - t0)

    t1 = time.perf_counter()
    df = spark.sql(QUERY)
    rows = df.collect()
    t_query = (time.perf_counter() - t1)

    result = {
        "engine": "databricks-connect-v2",
        "connect_s": round(t_connect, 3),
        "query_s": round(t_query, 3),
        "rows_returned": len(rows),
        "query_sample": QUERY[:120] + ("..." if len(QUERY) > 120 else ""),
    }
    print(json.dumps(result, indent=2))

if __name__ == "__main__":
    main()
