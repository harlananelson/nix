#!/usr/bin/env Rscript
suppressMessages({
  library(DBI); library(odbc); library(jsonlite)
})

server <- Sys.getenv("AZURE_SQL_SERVER")
database <- Sys.getenv("AZURE_DATABASE")
query <- Sys.getenv("BENCH_QUERY", "SELECT TOP 1000000 * FROM sys.objects a CROSS JOIN sys.objects b")

if (server == "" || database == "") {
  stop("Missing env: AZURE_SQL_SERVER / AZURE_DATABASE", call. = FALSE)
}

t0 <- proc.time()[["elapsed"]]
con <- dbConnect(odbc::odbc(),
                 Driver = "ODBC Driver 18 for SQL Server",
                 Server = server,
                 Database = database,
                 Encrypt = "yes",
                 TrustServerCertificate = "no",
                 Authentication = "ActiveDirectoryDeviceCode")
t_connect <- (proc.time()[["elapsed"]] - t0)

t1 <- proc.time()[["elapsed"]]
res <- dbGetQuery(con, query)
t_query <- (proc.time()[["elapsed"]] - t1)

out <- list(
  engine = "azure-sql-odbc-r",
  connect_s = round(t_connect, 3),
  query_s = round(t_query, 3),
  rows_returned = nrow(res),
  query_sample = paste0(substr(query, 1, 120), ifelse(nchar(query) > 120, "...", ""))
)
cat(prettify(toJSON(out, auto_unbox = TRUE)), "\n")
dbDisconnect(con)
