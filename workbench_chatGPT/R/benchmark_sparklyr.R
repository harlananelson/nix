#!/usr/bin/env Rscript
suppressMessages({
  library(sparklyr); library(dplyr); library(jsonlite)
})

host <- Sys.getenv("DATABRICKS_HOST")
token <- Sys.getenv("DATABRICKS_TOKEN")
cluster_id <- Sys.getenv("DATABRICKS_CLUSTER_ID", "")
warehouse_http_path <- Sys.getenv("DATABRICKS_WAREHOUSE_HTTP_PATH", "")
query <- Sys.getenv("DBX_BENCH_QUERY", "SELECT current_catalog() AS cat, current_schema() AS sch")

if (host == "" || token == "") {
  stop("Missing env: DATABRICKS_HOST / DATABRICKS_TOKEN", call. = FALSE)
}

# Prefer cluster method for compute; SQL Warehouses can be used via ODBC/JDBC too.
t0 <- proc.time()[["elapsed"]]
sc <- spark_connect(
  method = "databricks",
  envvars = list(
    DATABRICKS_HOST = host,
    DATABRICKS_TOKEN = token,
    DATABRICKS_CLUSTER_ID = cluster_id
  )
)
t_connect <- (proc.time()[["elapsed"]] - t0)

t1 <- proc.time()[["elapsed"]]
res <- spark_session(sc) %>% invoke("sql", query) %>% sdf_collect()
t_query <- (proc.time()[["elapsed"]] - t1)

out <- list(
  engine = "sparklyr-databricks",
  connect_s = round(t_connect, 3),
  query_s = round(t_query, 3),
  rows_returned = nrow(res),
  query_sample = paste0(substr(query, 1, 120), ifelse(nchar(query) > 120, "...", ""))
)
cat(prettify(toJSON(out, auto_unbox = TRUE)), "\n")
spark_disconnect(sc)
