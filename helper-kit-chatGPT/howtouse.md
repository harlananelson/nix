---
title: "Nix Development Environment Helper Kit"
format: html
date: today
author: "Your Name"
toc: true
---

## Overview

This helper kit provides a Makefile and smoke-test scripts to quickly validate your Nix shell environment and database connections for Python and R development.

## What's Included

The helper kit contains:

- **Makefile** with common development tasks
- **dev-smoke-python.sh** - Python smoke test script
- **dev-smoke-r.sh** - R smoke test script

## Setup Instructions

### Step 1: File Placement

Place these files beside your `flake.nix` (or in a subdirectory and adjust paths accordingly):

```bash
your-project/
├── flake.nix
├── Makefile
├── dev-smoke-python.sh
└── dev-smoke-r.sh
```

### Step 2: Environment Variables

Export the necessary environment variables for Azure SQL testing:

```bash
export AZURE_TENANT_ID="00000000-0000-0000-0000-000000000000"
export AZURE_SQL_SERVER="your-server.database.windows.net"
export AZURE_DATABASE="your_db"
```

**Optional:** For Databricks tests (separate from these smoke scripts):

```bash
export DATABRICKS_HOST="adb-xxxxxxxx.azuredatabricks.net"
export DATABRICKS_TOKEN="dapiXXXXX"
```

### Step 3: Usage Commands

Run the following make targets to validate your environment:

```bash
make dev        # enter the dev shell
make drivers    # confirm ODBC driver 18 is registered
make smoke      # runs python + r smoke tests inside the shell
make py-smoke   # just python test (token + SELECT 1)
make r-smoke    # just R device-code test
```

## Working with flake.lock

The `flake.lock` file should be generated on your machine to capture your exact nixpkgs revision for reproducibility.

### Generating flake.lock

```bash
# From the directory with your flake.nix
nix flake lock --update-input nixpkgs

# OR simply run (generates lock on first run if missing):
nix develop
```

This ensures your repository records the precise dependency graph you built with, making it more reproducible than using a generic lock file.

## Available Make Targets

| Target | Description |
|--------|-------------|
| `make dev` | Enter the Nix development shell |
| `make drivers` | Verify ODBC driver 18 registration |
| `make smoke` | Run both Python and R smoke tests |
| `make py-smoke` | Run Python smoke test only |
| `make r-smoke` | Run R smoke test only |

## Smoke Test Details

### Python Smoke Test
- Tests Azure authentication token acquisition
- Executes `SELECT 1` query against Azure SQL
- Validates Python database connectivity

### R Smoke Test  
- Tests R device-code authentication flow
- Validates R database connection capabilities
- Confirms R environment setup

## Optional Enhancements

The helper kit can be extended with additional scripts:

### CI Integration
- **`make ci-smoke`** target that exits non-zero on failures (useful for GitHub Actions)

### Enhanced Validation Scripts
- **`scripts/check-odbc.sh`** - Verifies `odbcinst.ini` contents and driver `.so` path existence
- **`scripts/keyring-health.sh`** - Sanity-check for headless keyring backend

## Troubleshooting

### Common Issues

1. **Missing environment variables**: Ensure all required Azure credentials are exported
2. **ODBC driver not found**: Run `make drivers` to verify driver registration
3. **Authentication failures**: Check your Azure tenant ID and credentials
4. **Nix shell issues**: Verify `flake.nix` is properly configured

### Debug Steps

```bash
# Check if in Nix shell
echo $NIX_SHELL

# Verify environment variables
env | grep AZURE

# Test ODBC driver registration
odbcinst -q -d
```

## Next Steps

After successful smoke tests:

1. Integrate the helper kit into your development workflow
2. Consider adding CI integration with `make ci-smoke`  
3. Extend with project-specific validation scripts
4. Document any additional environment requirements for your team￼