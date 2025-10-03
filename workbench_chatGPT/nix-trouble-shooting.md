Great—here’s a drop-in appendix section for your nix-troubleshooting.qmd plus a matching, minimal-but-complete flake.nix you can save next to it. This flake mirrors the log’s fixes: user-scoped ODBC driver registration, headless-safe auth, and a self-healing shellHook (no GUI auth; device-code/CLI only).

⸻

️⃣ Appendix block to paste into nix-troubleshooting.qmd

# A. Reproducible Dev Shell (flake.nix)

This appendix provides a minimal, pinned **Nix flake** that reproduces the working environment described in this log:

- Microsoft **ODBC Driver 18** present and **registered** (user-scoped `odbcinst.ini`)
- Headless-safe **Azure SQL** auth (R: `ActiveDirectoryDeviceCode`, Python: CLI → Device Code)
- `TMPDIR` set; quick **languageserver** bootstrap for VS Code R extension
- No plaintext secrets; recommend keyring/Key Vault per main doc

Save the file below as `flake.nix` in the repository root, then run:

```bash
nix develop       # or: nix develop .#devShells.x86_64-linux.default
# inside the shell:
odbcinst -q -d    # should list 'ODBC Driver 18 for SQL Server'

If you need FHS emulation for stubborn pathing issues, see the commented “Optional FHS shell” section inside the file.

A.1 flake.nix

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

A.2 Quick usage snippets

R (headless device code)

library(DBI); library(odbc)
con <- dbConnect(odbc::odbc(),
  Driver="ODBC Driver 18 for SQL Server",
  Server=Sys.getenv("AZURE_SQL_SERVER"),
  Database=Sys.getenv("AZURE_DATABASE"),
  Encrypt="yes", TrustServerCertificate="no",
  Authentication="ActiveDirectoryDeviceCode"
)
dbGetQuery(con, "SELECT TOP 1 name FROM sys.databases"); dbDisconnect(con)

Python (CLI → Device Code fallback, no GUI)

import struct, pyodbc
from azure.identity import DefaultAzureCredential, AzureCliCredential, DeviceCodeCredential
scope = "https://database.windows.net/.default"
try:
    tok = DefaultAzureCredential(exclude_interactive_browser_credential=True).get_token(scope).token
except Exception:
    try: tok = AzureCliCredential().get_token(scope).token
    except Exception: tok = DeviceCodeCredential(tenant_id="YOUR_TENANT_ID").get_token(scope).token
w = tok.encode("utf-16-le"); access = struct.pack("=i", len(w)) + w
cn = pyodbc.connect(
  "Driver={ODBC Driver 18 for SQL Server};Server="+
  "YOUR_SERVER.database.windows.net;Database=YOUR_DB;Encrypt=yes;TrustServerCertificate=no;",
  attrs_before={1256: access})
print("OK", cn.cursor().execute("SELECT 1").fetchone()); cn.close()


⸻

If you’d like, I can also generate a tiny flake.lock (pinned to current unstable) or a make dev helper to enter the shell and run a 10-second connectivity smoke test automatically.