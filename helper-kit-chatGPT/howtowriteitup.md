Added ✅
	•	CI-ready Makefile with ci-smoke, odbc-check, and keyring-check
	•	Health scripts:
	•	check-odbc.sh — verifies driver registration and the actual .so path
	•	keyring-health.sh — prints backend; optional write test
	•	GitHub Actions workflow:
	•	.github/workflows/ci-smoke.yml

And the updated Makefile:
	•	Makefile

How to wire it up

# Put the whole folder beside your flake.nix (or adjust -C path)
# Optional: run locally
make -C nix-troubleshooting-kit ci-smoke

# In CI (GitHub):
# 1) Commit the folder (including .github/workflows/ci-smoke.yml)
# 2) Add repo secrets if you want live Azure tests:
#    AZURE_TENANT_ID, AZURE_SQL_SERVER, AZURE_DATABASE
# 3) (Optional) For stricter keyring validation:
#    set KEYRING_WRITE_TEST=1 and KEYRING_STRICT=1 in the workflow env

Behavior notes
	•	ci-smoke always checks ODBC driver registration and path.
	•	Azure SQL tests auto-skip if env vars aren’t present.
	•	keyring-health.sh is advisory by default; make it fail CI by setting KEYRING_STRICT=1 (and optionally KEYRING_WRITE_TEST=1 to perform a safe write/delete roundtrip).

Want me to bundle these into a zip for easy download, or add a Quarto partial that loads the CI JSON output into your docs automatically? ￼