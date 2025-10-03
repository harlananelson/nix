## ROLE
Act as a meticulous Senior Data Engineer and Technical Writer conducting a post-implementation review for a headless, MFA-constrained, Nix-managed environment.

## TASK
Produce a single Quarto (`.qmd`) document that (a) **specifies** the target architecture and environment, (b) **reconstructs** the troubleshooting history, and (c) **analyzes** security and reproducibility (esp. secrets). The output must be production-ready.

## INPUTS
- [CONTEXT 1: System Requirements] … (paste)
- [CONTEXT 2: Connectivity Protocols] … (paste)
- [CONTEXT 3: Troubleshooting History] … (paste)
- [CONTEXT 4: Reference Doc(s)] … (paste/links)

## OUTPUT FORMAT (MANDATORY)
YAML:
```yaml
---
title: "Engineering Spec & Post-Implementation Review: Polyglot Data Environment"
author: "AI Assistant"
date: "current_date"
format:
  html:
    toc: true
    code-fold: true
    number-sections: true
---
```

Sections:
1. **Overview & Requirements**
   - 1.1 Executive Summary (≤150 words)
   - 1.2 Connectivity Architecture (Mermaid diagram: SSH → Dev Server → Protocols)
   - 1.3 Use-Case Matrix (Fully Remote / Hybrid / Local; compute locus; constraints)
2. **Environment & Build**
   - 2.1 Why Nix (repro, pinning, unfree notice)
   - 2.2 Final `flake.nix` (working, with ODBC driver registration + libsecret)
   - 2.3 Headless Keyring Backends (Secret Service/pass/Key Vault)
3. **Auth & Secrets (Headless-Safe)**
   - 3.1 Auth patterns: Device Code, CLI, Managed Identity, Service Principal  
     *For each*: code (R/Python), policy prerequisites, failure modes
   - 3.2 Secrets Management: keyring (`python`, `R`), libsecret, Databricks tokens, **no `.env` for secrets**
   - 3.3 Anti-Patterns: plaintext `.env`, `LD_LIBRARY_PATH` hacks, browser-only flows
4. **Connectivity Implementations**
   - 4.1 Azure SQL: Python `pyodbc` with token = UTF-16LE; R `Authentication=ActiveDirectoryDeviceCode`
   - 4.2 Databricks Connect v2: `DatabricksSession.builder.getOrCreate()`; note runtime/version match
   - 4.3 ADBC/Arrow (optional): when to prefer, current maturity limits
5. **Troubleshooting Log (Chronological)**
   - For each issue: Problem → Diagnosis → Attempts (incl. failures) → Final Outcome
6. **Validation & DoD**
   - Driver listing commands, token flow test, Databricks query returns rows, non-interactive success
7. **Recommendations & Next Steps**
   - ADBC evaluation plan, secrets rotation policy, CI checks
8. **Assumptions, Gaps, and References**
   - Bullet assumptions; list unresolved questions
   - Cite official docs/links used

## STYLE & CONSTRAINTS
- Headless-safe code only (no InteractiveBrowserCredential or GUI prompts).
- Prefer official docs; include inline links in §8.
- All secrets via keyring/Key Vault; `.env` only for non-sensitive config.
- Keep code blocks self-contained; annotate prerequisites.
- If a fact is uncertain, state it in §8 “Assumptions.”

## ACCEPTANCE CHECKLIST (the model must satisfy)
- [ ] Mermaid diagram renders
- [ ] `flake.nix` includes ODBC driver registration + libsecret
- [ ] R section shows `Authentication=ActiveDirectoryDeviceCode`
- [ ] Databricks section uses Connect v2 correctly
- [ ] Secrets handled via keyring; no plaintext tokens
- [ ] Troubleshooting includes failed attempts
- [ ] At least 3 official references cited