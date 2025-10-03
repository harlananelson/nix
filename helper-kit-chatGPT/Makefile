
# Simple helpers for the Nix troubleshooting dev shell
# Usage:
#   make dev        # enter dev shell
#   make smoke      # run all smoke tests inside the shell
#   make py-smoke   # Python ODBC token + SELECT 1
#   make r-smoke    # R ODBC device-code + SELECT 1
#   make drivers    # list registered ODBC drivers
#   make ci-smoke   # CI-friendly composite check (skips Azure tests if env missing)

SHELL := /bin/bash

.PHONY: dev smoke py-smoke r-smoke drivers ci-smoke odbc-check keyring-check

dev:
	@nix develop

drivers:
	@nix develop --command bash -lc 'echo "Drivers:"; odbcinst -q -d || true'

odbc-check:
	@nix develop --command bash -lc 'scripts/check-odbc.sh'

keyring-check:
	@nix develop --command bash -lc 'scripts/keyring-health.sh'

smoke: drivers odbc-check keyring-check py-smoke r-smoke

py-smoke:
	@nix develop --command bash -lc 'scripts/dev-smoke-python.sh'

r-smoke:
	@nix develop --command bash -lc 'scripts/dev-smoke-r.sh'

# CI target:
# - Always validates driver registration and odbcinst path
# - Keyring health is advisory by default (non-fatal); set KEYRING_STRICT=1 to make it fatal
# - Azure SQL tests only run if env vars are present; otherwise they are skipped
ci-smoke:
	@echo "== CI smoke start =="
	@$(MAKE) --no-print-directory drivers
	@$(MAKE) --no-print-directory odbc-check
	@ if [[ "$${KEYRING_STRICT:-0}" == "1" ]]; then \
	    $(MAKE) --no-print-directory keyring-check; \
	  else \
	    nix develop --command bash -lc 'scripts/keyring-health.sh || echo "[ci] keyring advisory failure (ignored)"; exit 0'; \
	  fi
	@ if [[ -n "$${AZURE_SQL_SERVER:-}" && -n "$${AZURE_DATABASE:-}" && -n "$${AZURE_TENANT_ID:-}" ]]; then \
	    $(MAKE) --no-print-directory py-smoke; \
	    $(MAKE) --no-print-directory r-smoke; \
	  else \
	    echo "[ci] Azure env vars not set; skipping SQL connectivity tests."; \
	  fi
	@echo "== CI smoke done =="
