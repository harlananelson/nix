---
title: "Nix Azure Data Development Environment"
format: html
date: today
author: "Development Team"
toc: true
code-fold: false
---

## Overview

This document provides a minimal, pinned Nix flake that creates a reproducible development environment for Azure SQL database work with R and Python. The environment includes headless authentication, proper ODBC driver registration, and VS Code integration.

## Features

The development shell includes:

- **Microsoft ODBC Driver 18** with proper user-scoped registration
- **Headless-safe Azure SQL** authentication (R: `ActiveDirectoryDeviceCode`, Python: CLI → Device Code)
- **TMPDIR** configuration and quick **languageserver** bootstrap for VS Code R extension
- **No plaintext secrets** - uses keyring/Key Vault as recommended

## Setup Instructions

### Step 1: Create the Flake

Save the following as `flake.nix` in your repository root:

```nix
{
  description = "Headless Azure Data Dev Shell (ODBC + R/Python)";

  inputs = {
    # Pin a known-good nixpkgs (update as needed)
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs {
          inherit system;
          config.allowUnfree = true;  # msodbcsql is unfree
        };
      in
      {
        devShells.default = pkgs.mkShell {
          buildInputs = with pkgs; [
            # --- ODBC + SQL Server driver ---
            unixODBC
            msodbcsql18

            # --- Python (headless auth + ODBC client libs) ---
            (python3.withPackages (ps: with ps; [
              pyodbc
              azure-identity         # Default/AzureCli/DeviceCode credentials
              keyring                # DO NOT rely on insecure fallback backends
              pandas
            ]))

            # --- R stack (headless device-code for ODBC) ---
            (rWrapper.override {
              packages = with rPackages; [
                odbc DBI keyring AzureAuth # R auth helpers + odbc
              ];
            })

            # --- optional helpers ---
            libsecret gnome-keyring   # only if you will run a Secret Service/DBus
            git curl jq ncurses       # niceties
          ];

          # Everything we fixed in the troubleshooting log is here:
          shellHook = ''
            set -eu

            # 1) Per-user ODBC registration (driver + optional DSN)
            mkdir -p "$HOME/.odbc" "$HOME/tmp"
            export ODBCSYSINI="$HOME/.odbc"
            export ODBCINI="$HOME/.odbc/odbc.ini"
            export TMPDIR="$HOME/tmp"

            ODBCINST="$HOME/.odbc/odbcinst.ini"
            if [ ! -s "$ODBCINST" ]; then
              cat > "$ODBCINST" <<EOF
[ODBC Drivers]
ODBC Driver 18 for SQL Server=Installed

[ODBC Driver 18 for SQL Server]
Description=Microsoft ODBC Driver 18 for SQL Server
Driver=${pkgs.msodbcsql18}/lib/libmsodbcsql-18.*.so
UsageCount=1
EOF
            fi

            if [ ! -s "$ODBCINI" ]; then
              cat > "$ODBCINI" <<'EOF'
[AzureSQL]
Driver=ODBC Driver 18 for SQL Server
Description=Azure SQL DB (token-based)
# Server=your-server.database.windows.net
# Database=your_db
# Encrypt=yes
# TrustServerCertificate=no
EOF
            fi

            # 2) Quietly ensure VS Code R LSP is available without baking into closure
            R -q -e 'if(!requireNamespace("languageserver", quietly=TRUE)) install.packages("languageserver")' \
              >/dev/null 2>&1 || true

            echo "Dev shell ready."
            echo "  ODBCSYSINI=$ODBCSYSINI"
            echo "  Drivers: $(odbcinst -q -d || echo 'N/A')"
          '';
        };

        # --- Optional: FHS shell for stubborn loader/path issues (use sparingly) ---
        # devShells.fhs = pkgs.buildFHSEnv {
        #   name = "fhs-env";
        #   targetPkgs = pkgs: with pkgs; [
        #     bashInteractive coreutils
        #     unixODBC msodbcsql18
        #     (python3.withPackages (ps: with ps; [ pyodbc azure-identity ]))
        #     (rWrapper.override { packages = with rPackages; [ odbc DBI ]; })
        #   ];
        #   runScript = "${pkgs.bashInteractive}/bin/bash";
        # };
      }
    );
}
```

### Step 2: Enter the Development Shell

```bash
nix develop       # or: nix develop .#devShells.x86_64-linux.default

# Verify ODBC driver registration:
odbcinst -q -d    # should list 'ODBC Driver 18 for SQL Server'
```

## Usage Examples

### R Connection (Headless Device Code)

```r
library(DBI)
library(odbc)

con <- dbConnect(odbc::odbc(),
  Driver = "ODBC Driver 18 for SQL Server",
  Server = Sys.getenv("AZURE_SQL_SERVER"),
  Database = Sys.getenv("AZURE_DATABASE"),
  Encrypt = "yes", 
  TrustServerCertificate = "no",
  Authentication = "ActiveDirectoryDeviceCode"
)

# Test connection
result <- dbGetQuery(con, "SELECT TOP 1 name FROM sys.databases")
print(result)

# Clean up
dbDisconnect(con)
```

### Python Connection (CLI → Device Code Fallback)

```python
import struct
import pyodbc
from azure.identity import (
    DefaultAzureCredential, 
    AzureCliCredential, 
    DeviceCodeCredential
)

# Get access token with fallback chain
scope = "https://database.windows.net/.default"
try:
    tok = DefaultAzureCredential(
        exclude_interactive_browser_credential=True
    ).get_token(scope).token
except Exception:
    try: 
        tok = AzureCliCredential().get_token(scope).token
    except Exception: 
        tok = DeviceCodeCredential(
            tenant_id="YOUR_TENANT_ID"
        ).get_token(scope).token

# Prepare token for ODBC
w = tok.encode("utf-16-le")
access = struct.pack("=i", len(w)) + w

# Connect to database
cn = pyodbc.connect(
    "Driver={ODBC Driver 18 for SQL Server};"
    "Server=YOUR_SERVER.database.windows.net;"
    "Database=YOUR_DB;"
    "Encrypt=yes;"
    "TrustServerCertificate=no;",
    attrs_before={1256: access}
)

# Test connection
cursor = cn.cursor()
result = cursor.execute("SELECT 1").fetchone()
print("Connection OK:", result)

# Clean up
cn.close()
```

## Environment Variables

Set these environment variables for your Azure setup:

```bash
export AZURE_SQL_SERVER="your-server.database.windows.net"
export AZURE_DATABASE="your_db"
export AZURE_TENANT_ID="your-tenant-id"  # for Python DeviceCode fallback
```

## Troubleshooting

### ODBC Driver Issues

If the ODBC driver isn't found:

```bash
# Check driver registration
odbcinst -q -d

# Verify driver file exists
ls -la ~/.odbc/odbcinst.ini

# Check environment variables
echo $ODBCSYSINI
echo $ODBCINI
```

### Authentication Issues

- **R**: Uses `ActiveDirectoryDeviceCode` - follow the device code prompts
- **Python**: Uses credential chain fallback - ensure `az login` is completed or device code flow works

### FHS Shell Alternative

If you encounter stubborn loader/path issues, uncomment the FHS shell section in the flake and use:

```bash
nix develop .#fhs
```

## Next Steps

This environment provides a solid foundation for Azure SQL development. Consider:

1. Adding project-specific R packages or Python dependencies
2. Creating Makefile targets for common development tasks  
3. Integrating with CI/CD pipelines using the same Nix environment
4. Adding additional Azure services as needed

The flake can be extended with additional tools and packages as your project requirements evolve.