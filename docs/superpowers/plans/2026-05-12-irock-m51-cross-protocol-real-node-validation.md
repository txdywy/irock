# M51 Cross-Protocol Real Node Validation Plan

## Tasks

1. Add RED tooling coverage.
   - Assert M51 spec, plan, protocol matrix, and real-node runbook exist.
   - Assert Alpha protocol matrix names all Alpha protocols and transports without example secrets.
   - Assert real-node runbook names required inputs, expected observations, redaction rules, external blockers, device/signing requirements, and do-not-commit guidance.

2. Add sanitized validation artifacts.
   - Create `tests/protocol-fixtures/ALPHA-PROTOCOL-MATRIX.md` using only sanitized fixture labels and no real credentials.
   - Create `tools/protocol-lab/REAL-NODE-VALIDATION.md` with manual execution steps and explicit external blockers.
   - Document that development-time comparison tools may use external engines, but the app runtime must not embed them.

3. Verify and review.
   - Run `swift test --filter ProtocolValidationTests`.
   - Run full `swift test`.
   - Scan for platform imports in shared packages.
   - Scan for signing/provisioning artifacts and obvious secret fixture strings.
   - Request independent review for credential safety and validation completeness.
   - Run bounded cleanup on M51 files only, then re-run verification.

4. Commit and push.
   - Update local Ralph state after verification.
   - Commit only M51 files, excluding `.omc/`, `.serena/`, and other local state.
