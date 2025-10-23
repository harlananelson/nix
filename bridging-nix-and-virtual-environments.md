# R/Qinglan_VitalSignsFeatures.R: Log run and execute a CTAS query using headless MFA (token from az cache).
library(lubridate)
library(glue) # Library for parameterized queries
library(here) # For here::here
library(targets) # For tar_read
library(dplyr) # For pull

# --- CONFIGURATION: Please verify this section ---
vitals_df <- tar_read(vital_signs)  # Dynamic from targets (your tibble with 10 rows)
vital_codes <- pull(vitals_df, TaskAssayCVCD)  # Extract codes (e.g., 39548732 for Systolic_BP)
log_file <- "logs/vital_signs_features.log"
# --- END CONFIGURATION ---

# Step 1: Log the script execution
log_entry <- paste(Sys.time(), "- R CTAS script run initiated")
writeLines(log_entry, log_file, sep = "\n") # Appends for history
cat("Successfully logged entry to", log_file, "\n")

# Step 2: Build the SQL query using R's glue (raw for DDL, no .con needed)
cat("Building SQL query...\n")
sql_query <- glue("
  IF OBJECT_ID('Reporting_Research.Qinglan_VitalSignsFeatures', 'U') IS NOT NULL
    DROP TABLE Reporting_Research.Qinglan_VitalSignsFeatures;
  CREATE TABLE Reporting_Research.Qinglan_VitalSignsFeatures WITH (
    DISTRIBUTION = HASH (PersonID),
    CLUSTERED COLUMNSTORE INDEX
  ) AS
  WITH cohort AS (
    SELECT PersonID, LabFirstOrderDate,
           DATEADD(DAY, 30, LabFirstOrderDate) AS first_month_end
    FROM Reporting_Research.Qinglan_Diabetes_History
  ),
  vitals AS (
    SELECT a.PersonID, a.TaskAssayCVCD,
           TRY_CAST(a.ResultVAL AS FLOAT) AS ResultVAL_NUM,
           a.EncounterCompleteDTS
    FROM Reporting_Research.Qinglan_VitalSignsEncounters AS a
    INNER JOIN cohort ON a.PersonID = cohort.PersonID
    WHERE a.EncounterCompleteDTS BETWEEN cohort.LabFirstOrderDate
                                     AND cohort.first_month_end
      AND a.TaskAssayCVCD IN ({paste(vital_codes, collapse = ', ')})
      AND TRY_CAST(a.ResultVAL AS FLOAT) IS NOT NULL
  )
  SELECT
    PersonID,
    TaskAssayCVCD,
    AVG(ResultVAL_NUM) AS mean_result,
    STDEV(ResultVAL_NUM) AS sd_result,
    MIN(ResultVAL_NUM) AS min_result,
    MAX(ResultVAL_NUM) AS max_result,
    COUNT(*) AS n_measurements
  FROM vitals
  GROUP BY PersonID, TaskAssayCVCD
")  # glue() for raw interpolation (no .con/quoting for DDL; manual IN clause)

# Step 3: Call the Python script to execute the query (venv Python + shell=TRUE for safe quoting)
cat("Handing off query to Python executor...\n")
py_result <- system2(
  here::here(".venv/bin/python"),  # Explicit venv Python (fixes ModuleNotFound)
  args = c(here::here("db_executor.py"), shQuote(sql_query)),  # shQuote escapes multi-line SQL
  shell = TRUE,  # Shell mode for safe arg passing
  stdout = TRUE,
  stderr = TRUE
)

# Step 4: Check the result and log the outcome
if (!is.null(attr(py_result, "status")) && attr(py_result, "status") != 0) {
  # The Python script exited with an error
  error_message <- paste("Execution failed. Output from Python:", paste(py_result, collapse="\n"))
  write(paste(Sys.time(), error_message), file = log_file, append = TRUE)
  stop(error_message)
} else {
  # Success
  success_message <- paste("✅ Execution successful. Output from Python:", paste(py_result, collapse="\n"))
  write(paste(Sys.time(), success_message), file = log_file, append = TRUE)
  cat(success_message, "\n")
}

cat("Process complete.\n")