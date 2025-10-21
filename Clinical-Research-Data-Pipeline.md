# Clinical Research Data Pipeline

A reproducible clinical research data pipeline using Python, R, and Databricks for querying and analyzing electronic health record (EHR) data from Cerner databases.

## Overview

This project implements a secure, MFA-authenticated data extraction and analysis pipeline for clinical research studies. It combines R's data analysis capabilities with Python's secure database authentication, enabling researchers to work with protected health information (PHI) while maintaining proper security protocols.

## Key Features

- **Secure Database Access**: Python-based executor with MFA authentication via Azure
- **Reproducible Workflows**: Uses `targets` package for R pipeline management
- **No Unity Catalog Write Access Required**: Uses SQL Server temp tables and R data objects as alternatives
- **Nix Environment**: Reproducible development environment
- **Mixed Language Support**: Python for authentication/execution, R for analysis

## Architecture

### Core Components

1. **Python SQL Executor** (`db_executor.py`)
   - Handles MFA authentication via Azure CLI
   - Executes SQL queries with proper credential management
   - Supports both `execute` (DDL/DML) and `query` (SELECT) modes

2. **R Helper Functions** (`R/functions.R`)
   - `execute_db()`: Execute SQL commands via Python executor
   - `query_db()`: Query data and return as R data.table
   - `log_message()`: Centralized logging

3. **Targets Pipeline** (`_targets.R`)
   - Orchestrates data extraction and feature engineering
   - Manages dependencies between analysis steps
   - Caches intermediate results

## Project Structure

```
.
├── R/                           # R scripts for data extraction
│   ├── functions.R              # Helper functions
│   ├── Qinglan_***.R           # Feature extraction scripts
│   └── prep_*.R                 # Data preparation scripts
├── inst/raw/                    # Reference data (lab codes, measurements, etc.)
├── HOWTO/                       # Documentation and guides
│   ├── Writing-R-Scripts-for-the-Python-SQL-Execution-Pipeline.md
│   └── bridging-nix-and-virtual-environments.md
├── logs/                        # Execution logs
├── _targets.R                   # Targets pipeline definition
├── db_executor.py               # Python SQL executor
├── *.qmd                        # Quarto analysis documents
├── flake.nix                    # Nix environment definition
└── README.md                    # This file
```

## Getting Started

### Prerequisites

- Nix package manager (for reproducible environment)
- Azure CLI (for MFA authentication)
- Access to IU Health EDW database
- Python 3.9+ with virtual environment
- R 4.0+ with required packages

### Installation

1. **Clone the repository**
   ```bash
   git clone <repository-url>
   cd <project-directory>
   ```

2. **Set up Nix environment**
   ```bash
   nix develop
   ```

3. **Set up Python virtual environment**
   ```bash
   python -m venv .venv
   source .venv/bin/activate
   pip install -r requirements.txt
   ```

4. **Install R packages**
   ```r
   install.packages(c("targets", "data.table", "dplyr", "dbplyr", 
                      "DBI", "odbc", "here", "glue", "arrow"))
   ```

5. **Configure Azure authentication**
   ```bash
   az login
   ```

### Configuration

Create a `.env` file (not tracked in git) with your credentials:
```bash
DB_SERVER=your_server
DB_DATABASE=your_database
DB_UID=your_username
```

## Usage

### Running the Full Pipeline

```bash
# In R console
targets::tar_make()

# Or from command line
Rscript -e "targets::tar_make()"
```

### Checking Pipeline Status

```r
# View pipeline visualization
targets::tar_visnetwork()

# Check which targets are outdated
targets::tar_outdated()

# Load a specific target
targets::tar_load(diabetes_labs)
```

### Writing New R Scripts

Follow the pattern in HOWTO documents:

```r
library(glue)
library(here)

# Step 1: Define your SQL query
sql_query <- glue("
  IF OBJECT_ID('Reporting_Research.MyNewTable', 'U') IS NOT NULL
    DROP TABLE Reporting_Research.MyNewTable;
  
  CREATE TABLE Reporting_Research.MyNewTable WITH (
    DISTRIBUTION = HASH (PersonID),
    CLUSTERED COLUMNSTORE INDEX
  ) AS
  SELECT * FROM SourceTable
  WHERE condition = 'value';
")

# Step 2: Execute via Python executor
source(here::here("R", "functions.R"))
execute_db(sql_query)
```

### Querying Data

```r
# Query data and return as data.table
result <- query_db("SELECT TOP 10 * FROM MyTable")
```

## Workflow Pattern

1. **Data Extraction**: R scripts create SQL tables using Python executor
2. **Feature Engineering**: Transform raw data into analysis-ready features
3. **Analysis**: Use Quarto documents for statistical analysis and reporting
4. **Reproducibility**: Targets tracks dependencies and only reruns changed steps

## Security Considerations

- **Never commit credentials** to version control
- **Use Azure MFA** for all database connections
- **PHI Handling**: Follow HIPAA guidelines for data storage and sharing
- **Log files** may contain query text but never credential information
- **.gitignore** is configured to exclude sensitive files

## Databricks Limitations & Workarounds

### No Unity Catalog Write Access

Since you don't have write access to Unity Catalog, this system uses:

1. **SQL Server Temp Tables**: Create tables in `Reporting_Research` schema
2. **R Data Objects**: Use `targets` to cache data as RDS files
3. **TxtArchive**: Archive analysis code for sharing without data

### Alternative Storage Solutions

- **Arrow/Parquet**: Store intermediate results as files
- **Data.table RDS**: Serialize R objects for fast loading
- **CSV Export**: For sharing with collaborators

## Documentation

- **HOWTO/Writing-R-Scripts-for-the-Python-SQL-Execution-Pipeline.md**: Pattern for new R scripts
- **HOWTO/bridging-nix-and-virtual-environments.md**: Managing Python/R integration
- **Project-specific QMD files**: Analysis documentation

## Logging

All scripts log to `logs/` directory:
```bash
# View recent logs
tail -f logs/diabetes_labs.log

# Search for errors
grep "ERROR" logs/*.log
```

## Troubleshooting

### Common Issues

**Azure Authentication Fails**
```bash
# Re-authenticate
az login
az account show
```

**Python Module Not Found**
```bash
# Ensure virtual environment is activated
source .venv/bin/activate
pip install -r requirements.txt
```

**R Package Issues**
```r
# Check R can find Python
reticulate::py_config()

# Verify here() points to project root
here::here()
```

**ODBC Connection Errors**
- Verify ODBC driver is installed
- Check connection string in `db_executor.py`
- Ensure you're on VPN/network with database access

## Contributing

When adding new features:

1. Create R script following existing patterns
2. Add target to `_targets.R`
3. Document in appropriate HOWTO file
4. Test with `targets::tar_make()`
5. Archive code with txtarchive before sharing

## Citation

If you use this pipeline in your research, please cite:
```
[Your institution/research group]
Clinical Research Data Pipeline
[Year]
```

## License

This project contains protected health information (PHI) and is not for public distribution. Access is restricted to authorized IU Health research personnel.

## Contact

For questions or issues:
- [Your Name/Team]
- [Email]
- [Internal documentation link]

## Acknowledgments
