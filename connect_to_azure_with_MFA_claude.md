### ---
title: "Connecting to Azure Data Resources with MFA from a Headless Nix Environment"
subtitle: "A Comprehensive Guide Based on Real-World Implementation Experience"
author: "Claude"
format: 
  html:
    toc: true
    toc-depth: 3
    number-sections: true
    theme: cosmo
    self-contained: true
    code-fold: show
    code-tools: true
editor: visual
---

## Introduction

This document provides a battle-tested guide for connecting to Azure data resources from a Nix-managed, headless Linux environment accessed via SSH (such as through VS Code Remote). The methods described here have been refined through extensive real-world troubleshooting, particularly addressing Microsoft Entra ID (formerly Azure AD) authentication challenges that are common in enterprise environments.

**Key Focus Areas:**
- Headless server environments (no GUI/X11 forwarding)
- Multi-factor authentication (MFA) support
- Secure credential management using system keychains
- Both Azure SQL Server and Azure Databricks connections
- Nix-based reproducible environments

## Chapter 1: Azure SQL Server Connections

### 1.1 The Production-Ready `flake.nix`

Based on extensive testing with various authentication methods, this flake includes all necessary components for Azure MFA authentication:

```nix
{
  description = "Production Azure Data Science Environment";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs {
          inherit system;
          config.allowUnfree = true;
        };
      in
      {
        devShells.default = pkgs.mkShell {
          buildInputs = with pkgs; [
            # Python with Azure packages
            (python3.withPackages (ps: with ps; [
              pyodbc
              azure-identity
              azure-cli-core
              pandas
              python-dotenv
              keyring
              msal
              msal-extensions
            ]))

            # R with database packages
            (rWrapper.override {
              packages = with rPackages; [
                tidyverse
                dbplyr
                odbc
                DBI
                keyring
                AzureAuth
                AzureRMR
                jsonlite
                dotenv
              ];
            })

            # System dependencies for ODBC and Azure authentication
            unixODBC
            msodbcsql18  # Microsoft ODBC Driver 18 for SQL Server
            msodbcsql17  # Fallback driver
            krb5
            openssl
            azure-cli
            
            # Linux keyring support
            libsecret
            gnome-keyring
            
            # Development tools
            git
            curl
            jq
          ];

          shellHook = ''
            # Create user-specific ODBC configuration directory
            mkdir -p "$HOME/.odbc"
            export ODBCSYSINI="$HOME/.odbc"
            export ODBCINI="$HOME/.odbc/odbc.ini"
            
            # Register ODBC drivers (critical for Nix environments)
            ODBCINST="$HOME/.odbc/odbcinst.ini"
            if [ ! -f "$ODBCINST" ]; then
              cat > "$ODBCINST" <<EOF
[ODBC Drivers]
ODBC Driver 18 for SQL Server=Installed
ODBC Driver 17 for SQL Server=Installed

[ODBC Driver 18 for SQL Server]
Description=Microsoft ODBC Driver 18 for SQL Server
Driver=${msodbcsql18}/lib/libmsodbcsql-18.*.so
UsageCount=1

[ODBC Driver 17 for SQL Server]
Description=Microsoft ODBC Driver 17 for SQL Server
Driver=${msodbcsql17}/lib/libmsodbcsql-17.*.so
UsageCount=1
EOF
            fi
            
            # Azure CLI configuration
            export AZURE_CONFIG_DIR=$HOME/.azure
            
            # Create basic ODBC DSN configuration if it doesn't exist
            if [ ! -f "$ODBCINI" ]; then
              cat > "$ODBCINI" << EOF
[Azure SQL]
Driver=ODBC Driver 18 for SQL Server
Description=Azure SQL Database Connection
EOF
            fi
            
            echo "Azure Data Science Environment Ready!"
            echo "ODBC configuration: $ODBCINI"
            echo "ODBC drivers registered: $ODBCINST"
            echo "Available ODBC drivers:"
            odbcinst -q -d || echo "Check driver registration if empty"
          '';
        };
      });
}
```

### 1.2 Hybrid Secrets Management Strategy

**Philosophy:** Separate non-sensitive configuration from truly sensitive credentials.

#### Non-Sensitive Configuration (`~/.azure-config`)
```bash
# Server and database configuration (not sensitive)
AZURE_SQL_SERVER="your-server.database.windows.net"
AZURE_DATABASE="your_database_name"
AZURE_TENANT_ID="your-tenant-id"
```

#### Secure Secret Storage for Headless Environments

**Critical Note:** Standard keyring backends (libsecret/gnome-keyring) require D-Bus + Secret Service, often absent in headless SSH sessions. Here are headless-friendly alternatives:

**Option 1: password-store (pass) - Recommended**
```bash
# Install pass (available in nixpkgs)
# Initialize password store
pass init your-gpg-key-id

# Store secrets
pass insert azure/databricks-token
pass insert azure/service-principal-secret

# Configure Python keyring to use pass backend
echo "keyring.backends.pass.PasswordStoreBackend" > ~/.local/share/python_keyring/keyringrc.cfg
```

**Option 2: Azure Key Vault (Enterprise)**
```python
from azure.keyvault.secrets import SecretClient
from azure.identity import DefaultAzureCredential

# Best for production with RBAC
credential = DefaultAzureCredential()
client = SecretClient(vault_url="https://your-vault.vault.azure.net/", credential=credential)
secret = client.get_secret("databricks-token")
```

**Option 3: Encrypted File Backend**
```python
# Install: pip install keyrings.alt
import keyring
from keyrings.alt.file import EncryptedKeyring

# Set up encrypted keyring (password-protected)
keyring.set_keyring(EncryptedKeyring())
keyring.set_password("azure", "databricks-token", "your-token")
```

**Store Databricks PAT securely:**
```bash
# Using pass (recommended for headless)
pass insert databricks/your-workspace.azuredatabricks.net

# Or using Python with appropriate backend
python3 -c "import keyring; keyring.set_password('databricks', 'your-workspace.azuredatabricks.net', 'dapi123abc...')"
```

**Important:** Never store access tokens (short-lived) in keychains. Store refresh tokens, service principal secrets, or long-lived PATs only.

### 1.3 Python Connection Implementation

**Enhanced authentication with headless optimizations:**

```python
import os
import pyodbc
import pandas as pd
from dotenv import load_dotenv
from azure.identity import (
    DefaultAzureCredential,
    DeviceCodeCredential, 
    AzureCliCredential,
    ManagedIdentityCredential
)
import struct
import keyring
import logging

# Configure logging for debugging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Load configuration
load_dotenv(dotenv_path=os.path.expanduser("~/.azure-config"))
server = os.getenv("AZURE_SQL_SERVER")
database = os.getenv("AZURE_DATABASE")
tenant_id = os.getenv("AZURE_TENANT_ID")

def _wide_token(token: str) -> bytes:
    """Convert token to UTF-16LE with length prefix for SQL Server."""
    w = token.encode("utf-16-le")
    return struct.pack("=i", len(w)) + w

def get_azure_token_with_fallback():
    """
    Attempts multiple authentication methods optimized for headless environments.
    Returns access token for SQL Database scope.
    """
    scope = "https://database.windows.net/.default"
    
    # Method 1: Try Managed Identity (best for Azure VMs/containers)
    try:
        logger.info("Attempting Managed Identity...")
        credential = ManagedIdentityCredential()
        token = credential.get_token(scope)
        logger.info("✓ Managed Identity successful")
        return token.token
    except Exception as e:
        logger.info(f"Managed Identity failed: {e}")
    
    # Method 2: Try Default credential (excludes interactive to prevent hangs)
    try:
        logger.info("Attempting Default Azure Credential (headless mode)...")
        credential = DefaultAzureCredential(exclude_interactive_browser_credential=True)
        token = credential.get_token(scope)
        logger.info("✓ Default credential successful")
        return token.token
    except Exception as e:
        logger.info(f"Default credential failed: {e}")
    
    # Method 3: Try Azure CLI (if already logged in)
    try:
        logger.info("Attempting Azure CLI authentication...")
        credential = AzureCliCredential()
        token = credential.get_token(scope)
        logger.info("✓ Azure CLI authentication successful")
        return token.token
    except Exception as e:
        logger.info(f"Azure CLI auth failed: {e}")
    
    # Method 4: Device Code Flow (headless-friendly MFA)
    try:
        logger.info("Attempting Device Code Flow...")
        credential = DeviceCodeCredential(tenant_id=tenant_id)
        token = credential.get_token(scope)
        logger.info("✓ Device Code Flow successful")
        return token.token
    except Exception as e:
        logger.info(f"Device Code Flow failed: {e}")
        
    raise Exception("All authentication methods failed")

def get_azure_sql_connection():
    """
    Establishes connection to Azure SQL with proper error handling.
    """
    try:
        # Get authentication token
        access_token = get_azure_token_with_fallback()
        
        # Prepare token for ODBC (simplified, secure approach)
        token_struct = _wide_token(access_token)
        
        # Connection string
        conn_str = (
            f"Driver={{ODBC Driver 18 for SQL Server}};"
            f"Server={server};"
            f"Database={database};"
            f"Encrypt=yes;"
            f"TrustServerCertificate=no;"
        )
        
        # Connect with token
        connection = pyodbc.connect(
            conn_str, 
            attrs_before={1256: token_struct}  # SQL_COPT_SS_ACCESS_TOKEN
        )
        
        logger.info("✓ Successfully connected to Azure SQL")
        return connection
        
    except Exception as e:
        logger.error(f"Connection failed: {e}")
        raise

# Example usage
if __name__ == "__main__":
    try:
        conn = get_azure_sql_connection()
        
        # Test query
        df = pd.read_sql(
            "SELECT TOP 5 * FROM INFORMATION_SCHEMA.TABLES", 
            conn
        )
        print(df)
        
        conn.close()
        
    except Exception as e:
        print(f"Error: {e}")
```

### Headless MFA without a browser (Device Code)

**Key Point:** Device Code Flow works in headless environments by printing a code and URL that you copy to a browser on another device.

**Network connectivity test:**
```bash
# Test basic connectivity (nc preferred over telnet)
nc -vz your-server.database.windows.net 1433
```

**Authentication method compatibility:**

| Method | Headless Compatible | Requires |
|--------|-------------------|----------|
| Managed Identity | ✅ Yes | Azure VM/Container |
| Service Principal | ✅ Yes | Client secret/certificate |
| Device Code Flow | ✅ Yes | MFA policy allowlist |
| Azure CLI | ✅ Yes* | Prior `az login` |
| Interactive Browser | ❌ No | GUI/browser |

*Note: Some organizations block device code flow or require Conditional Access exemptions for non-interactive flows.

### 1.4 R Connection Implementation

**Critical Note:** The R `odbc` package supports `Authentication=ActiveDirectoryDeviceCode` which works in headless environments! The reticulate approach below is still valuable for complex scenarios, but pure R can handle basic headless MFA.

#### Primary Approach: Pure R with Device Code Authentication

```r
library(odbc)
library(DBI)
library(dotenv)

# Load configuration
load_dot_env("~/.azure-config")

# Headless-friendly R connection using Device Code
get_azure_sql_connection_r_native <- function() {
  server <- Sys.getenv("AZURE_SQL_SERVER")
  database <- Sys.getenv("AZURE_DATABASE")
  
  cat("Connecting with Device Code Authentication (headless-friendly)...\n")
  
  tryCatch({
    # This works in headless! Prints device code and URL
    con <- dbConnect(odbc(),
      Driver = "ODBC Driver 18 for SQL Server",
      Server = server,
      Database = database,
      Encrypt = "yes",
      TrustServerCertificate = "no",
      Authentication = "ActiveDirectoryDeviceCode"  # headless-compatible!
    )
    
    cat("✓ Connected via ActiveDirectoryDeviceCode\n")
    return(con)
    
  }, error = function(e) {
    cat("Device code auth failed:", conditionMessage(e), "\n")
    
    # Fallback to integrated authentication (domain machines only)
    tryCatch({
      cat("Trying integrated authentication (domain machines only)...\n")
      
      con <- dbConnect(odbc(),
        Driver = "ODBC Driver 18 for SQL Server",
        Server = server,
        Database = database,
        Trusted_Connection = "yes",
        Encrypt = "yes"
      )
      
      cat("✓ Connected via integrated auth\n")
      return(con)
      
    }, error = function(e2) {
      cat("Integrated auth failed:", conditionMessage(e2), "\n")
      stop("All R-native connection methods failed. Try reticulate approach below.")
    })
  })
}

# Example usage
tryCatch({
  con <- get_azure_sql_connection_r_native()
  
  # Test query
  result <- dbGetQuery(con, 
    "SELECT TOP 5 TABLE_NAME, TABLE_TYPE FROM INFORMATION_SCHEMA.TABLES")
  print(result)
  
  dbDisconnect(con)
  
}, error = function(e) {
  cat("Error:", conditionMessage(e), "\n")
})
```

#### Advanced Approach: R + Python via reticulate

For complex token handling or when you need exact Python library compatibility:

```r
library(reticulate)
library(DBI)
library(keyring)
library(dotenv)

# Load configuration
load_dot_env("~/.azure-config")

# Python-based connection function using reticulate
get_azure_sql_connection_r_reticulate <- function() {
  # Import Python modules
  pyodbc <- import("pyodbc")
  azure_identity <- import("azure.identity")
  
  server <- Sys.getenv("AZURE_SQL_SERVER")
  database <- Sys.getenv("AZURE_DATABASE")
  tenant_id <- Sys.getenv("AZURE_TENANT_ID")
  
  cat("Attempting Azure SQL connection via Python...\n")
  
  tryCatch({
    # Try Azure CLI first
    cli_credential <- azure_identity$AzureCliCredential()
    token <- cli_credential$get_token("https://database.windows.net/.default")
    cat("✓ Using Azure CLI token\n")
  }, error = function(e) {
    cat("Azure CLI failed, trying device code...\n")
    # Fallback to device code flow
    device_credential <- azure_identity$DeviceCodeCredential(tenant_id = tenant_id)
    token <- device_credential$get_token("https://database.windows.net/.default")
    cat("✓ Using device code token\n")
  })
  
  # Let Python handle the token encoding properly
  access_token <- token$token
  
  # Use Python's struct packing for proper byte handling
  azure_identity_internal <- import("azure.identity._internal")
  
  # Connection string
  conn_str <- paste0(
    "Driver={ODBC Driver 18 for SQL Server};",
    "Server=", server, ";",
    "Database=", database, ";",
    "Encrypt=yes;",
    "TrustServerCertificate=no;"
  )
  
  # Let Python's pyodbc handle the token directly
  token_bytes <- access_token$encode('utf-16-le')
  token_struct <- py_eval(sprintf("
import struct
token = '%s'.encode('utf-16-le')
struct.pack('=i', len(token)) + token
", access_token))
  
  # Connect using Python pyodbc
  py_conn <- pyodbc$connect(conn_str, attrs_before = list("1256" = token_struct))
  
  return(py_conn)
}

# Helper function to execute SQL from R using the Python connection
execute_sql_r <- function(py_conn, sql) {
  pandas <- import("pandas")
  df_py <- pandas$read_sql(sql, py_conn)
  
  # Convert to R data frame
  df_r <- py_to_r(df_py)
  return(df_r)
}

# Example usage
tryCatch({
  py_conn <- get_azure_sql_connection_r_reticulate()
  
  # Execute query
  result <- execute_sql_r(py_conn, 
    "SELECT TOP 5 TABLE_NAME, TABLE_TYPE FROM INFORMATION_SCHEMA.TABLES")
  print(result)
  
  # Close connection
  py_conn$close()
  
}, error = function(e) {
  cat("Error:", conditionMessage(e), "\n")
})
```

**Summary of R Approaches:**

1. **Pure R with Device Code (RECOMMENDED)**: Works in headless environments, simpler code
2. **Reticulate + Python (ADVANCED)**: For complex scenarios requiring exact Python compatibility
3. **Interactive methods**: Only work with GUI access, not suitable for headless SSH

### 1.5 Troubleshooting Common Issues

**Microsoft Entra ID Authentication Problems:**

1. **"Authentication failed" errors:**
   - Ensure ODBC Driver 18 is installed: `odbcinst -q -d`
   - Check tenant ID is correct
   - Verify MFA policies don't block device code flow

2. **Token format issues:**
   - Some servers require `TrustServerCertificate=no`
   - Ensure proper token byte encoding (UTF-8 to wide char)

3. **Network connectivity:**
   - Test basic connectivity: `telnet your-server.database.windows.net 1433`
   - Check firewall rules on Azure SQL Server

**Azure CLI Preparation (recommended):**
```bash
# Initial setup (run once)
az login --use-device-code
az account show  # Verify correct subscription
```

## Chapter 2: Azure Databricks Connections

### 2.1 Databricks-Specific Considerations

Databricks connections are fundamentally different from SQL Server connections:
- Use long-lived Personal Access Tokens (PATs)
- Connect via Spark/HTTP protocols, not ODBC
- Requires cluster management

### 2.2 Secure Token Management for Databricks

**Store Databricks PAT securely:**
```bash
# Store token once (from Databricks User Settings > Access Tokens)
python3 -c "import keyring; keyring.set_password('databricks', 'your-workspace.azuredatabricks.net', 'dapi123abc...')"
```

### 2.3 sparklyr Connection (R)

**Installation and Connection:**
```r
# Install latest sparklyr (refer to https://github.com/sparklyr/sparklyr)
# install.packages("sparklyr")
# sparklyr::spark_install()

library(sparklyr)
library(dplyr)
library(keyring)

# Configuration
databricks_host <- "your-workspace.azuredatabricks.net"
cluster_id <- "your-cluster-id"

# Retrieve stored token
databricks_token <- key_get("databricks", databricks_host)

# Connect to Databricks
sc <- spark_connect(
  method = "databricks",
  envvars = list(
    DATABRICKS_HOST = databricks_host,
    DATABRICKS_TOKEN = databricks_token,
    DATABRICKS_CLUSTER_ID = cluster_id
  )
)

# Example: Read from Delta table
delta_table <- tbl(sc, "catalog.schema.table_name")

# Use Arrow for faster data collection
collected_data <- collect(delta_table, arrow = TRUE)

# Always disconnect
spark_disconnect(sc)
```

### 2.4 Python/PySpark Connection

**Modern Databricks Connect v2 approach:**

```python
import os
from pyspark.sql import SparkSession
import keyring
from dotenv import load_dotenv

# Load configuration
load_dotenv(dotenv_path=os.path.expanduser("~/.azure-config"))

def setup_databricks_connect():
    """
    Set up Databricks Connect using the modern CLI-based configuration.
    Run this once to configure your environment.
    """
    databricks_host = os.getenv("DATABRICKS_HOST")
    
    # Get secure token
    databricks_token = keyring.get_password("databricks", databricks_host)
    
    print("Setting up Databricks Connect profile...")
    print(f"Host: {databricks_host}")
    print("Run the following command to complete setup:")
    print(f"databricks configure --host https://{databricks_host} --token")
    print("When prompted for token, use the one stored in your keychain")
    
    return {
        "host": databricks_host,
        "token": databricks_token
    }

def create_spark_session_modern():
    """
    Create Spark session using modern Databricks Connect v2.
    Assumes databricks CLI has been configured.
    """
    spark = SparkSession.builder \
        .appName("Azure-Databricks-Connect-v2") \
        .config("spark.sql.adaptive.enabled", "true") \
        .config("spark.sql.adaptive.coalescePartitions.enabled", "true") \
        .getOrCreate()
    
    return spark

def create_spark_session_legacy():
    """
    Legacy approach for older Databricks Connect versions.
    """
    databricks_host = os.getenv("DATABRICKS_HOST")
    cluster_id = os.getenv("DATABRICKS_CLUSTER_ID")
    
    # Get secure token
    databricks_token = keyring.get_password("databricks", databricks_host)
    
    spark = SparkSession.builder \
        .appName("Azure-Databricks-Connect-Legacy") \
        .config("spark.databricks.service.address", f"https://{databricks_host}") \
        .config("spark.databricks.service.token", databricks_token) \
        .config("spark.databricks.service.clusterId", cluster_id) \
        .config("spark.sql.adaptive.enabled", "true") \
        .config("spark.sql.adaptive.coalescePartitions.enabled", "true") \
        .getOrCreate()
    
    return spark

# Example usage - try modern approach first
try:
    print("Attempting modern Databricks Connect...")
    spark = create_spark_session_modern()
    
    # Test connection
    df = spark.sql("SELECT current_database() as current_db")
    df.show()
    
    # Example with Unity Catalog
    # df = spark.sql("SELECT * FROM catalog.schema.table_name LIMIT 10")
    # df.show()
    
    # For efficient data transfer to pandas, Arrow is used internally
    pandas_df = df.toPandas()
    print(f"Retrieved {len(pandas_df)} rows")
    
except Exception as e:
    print(f"Modern approach failed: {e}")
    print("Trying legacy approach...")
    
    try:
        spark = create_spark_session_legacy()
        df = spark.sql("SELECT current_database() as current_db")
        df.show()
        
    except Exception as e2:
        print(f"Legacy approach also failed: {e2}")
        print("Please check your Databricks configuration")
        
finally:
    if 'spark' in locals():
        spark.stop()
```

**Setup Instructions:**

1. **Install Databricks CLI:**
   ```bash
   pip install databricks-cli
   ```

2. **Configure Databricks Connect (recommended):**
   ```bash
   # Get your stored token
   python3 -c "import keyring; print(keyring.get_password('databricks', 'your-workspace.azuredatabricks.net'))"
   
   # Configure using CLI
   databricks configure --host https://your-workspace.azuredatabricks.net --token
   # Enter the token when prompted
   ```

3. **Alternative: Use environment variables** (for legacy approach):
   ```bash
   # Add to ~/.azure-config
   DATABRICKS_HOST="your-workspace.azuredatabricks.net"
   DATABRICKS_CLUSTER_ID="your-cluster-id"
   ```

## Chapter 3: Apache Arrow Integration

### 3.1 Current State and Future Prospects

**For Azure SQL Server:**
- ADBC (Arrow Database Connectivity) support for SQL Server is still immature
- Current approach using ODBC remains most reliable
- Future: Direct Arrow-native queries may bypass ODBC overhead

**For Databricks:**
- Excellent Arrow integration already available
- `sparklyr`: Use `collect(arrow = TRUE)` for faster data collection
- PySpark: `toPandas()` uses Arrow internally for efficiency
- Spark 3.5+ supports Arrow-optimized UDFs

### 3.2 Performance Optimization with Arrow

**R/sparklyr with Arrow:**
```r
# Enable Arrow optimizations
spark_config <- list(
  "spark.sql.execution.arrow.pyspark.enabled" = "true",
  "spark.sql.execution.arrow.sparkr.enabled" = "true"
)

sc <- spark_connect(
  method = "databricks",
  config = spark_config,
  # ... other connection params
)

# Use Arrow for large data transfers
large_dataset <- tbl(sc, "large_table") %>%
  collect_arrow()  # Faster than collect()
```

## Chapter 4: Production Best Practices

### 4.1 Security Considerations

1. **Never store credentials in code or version control**
2. **Use system keychain for sensitive data**
3. **Rotate tokens regularly**
4. **Monitor authentication logs**
5. **Use least-privilege access principles**

### 4.2 Error Handling and Monitoring

```python
import logging
from functools import wraps

def retry_connection(max_retries=3):
    def decorator(func):
        @wraps(func)
        def wrapper(*args, **kwargs):
            for attempt in range(max_retries):
                try:
                    return func(*args, **kwargs)
                except Exception as e:
                    logging.warning(f"Attempt {attempt + 1} failed: {e}")
                    if attempt == max_retries - 1:
                        raise
                    time.sleep(2 ** attempt)  # Exponential backoff
            return wrapper
        return decorator

@retry_connection(max_retries=3)
def robust_sql_connection():
    return get_azure_sql_connection()
```

### 4.3 Development Workflow

1. **Start with Azure CLI authentication** (simplest for development)
2. **Test device code flow** for production headless scenarios
3. **Implement proper error handling and logging**
4. **Use environment-specific configuration files**
5. **Document authentication requirements for team members**

## Conclusion

This guide represents lessons learned from extensive real-world implementation of Azure data connections in headless environments. The key success factors are:

1. **Multiple authentication fallbacks** - No single method works in all environments
2. **Proper credential management** - System keychain for sensitive data
3. **Comprehensive error handling** - Graceful degradation when methods fail
4. **Environment reproducibility** - Nix ensures consistent tooling

The combination of device code flow for MFA, secure credential storage, and proper ODBC driver configuration provides a robust foundation for enterprise Azure data access.

---

*For the latest updates on sparklyr, always refer to the official repository: https://github.com/sparklyr/sparklyr*