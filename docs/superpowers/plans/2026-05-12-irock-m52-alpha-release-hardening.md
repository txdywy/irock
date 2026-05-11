# M52 Alpha Release Hardening Plan

## Tasks

1. Add RED release readiness tests.
   - Assert M52 spec, plan, and release readiness evidence exist.
   - Assert readiness evidence covers M30 through M52.
   - Assert readiness evidence mentions protocol matrix, iOS shell, macOS shell, routing, diagnostics, performance budget, external blocker, full swift test, and signing artifact scan.
   - Assert obvious secret sentinel strings and private key markers are absent.

2. Add release readiness evidence.
   - Create `docs/superpowers/release/ALPHA-READINESS.md`.
   - Summarize milestone evidence and remaining external blockers.
   - Keep credentials, signing artifacts, raw logs, and node URIs out of the repository.

3. Verify and review.
   - Run `swift test --filter ReleaseReadinessTests`.
   - Run full `swift test`.
   - Scan shared packages for platform imports.
   - Scan app folders for signing/provisioning artifacts.
   - Scan release readiness files for obvious secret markers.
   - Request independent release-readiness review.
   - Run bounded cleanup on M52 files only, then re-run verification.

4. Commit, push, and exit Ralph.
   - Mark M52 complete in local Ralph state after verification.
   - Commit only M52 files, excluding `.omc/`, `.serena/`, and other local state.
   - Push the M52 commit.
   - Run `/oh-my-claudecode:cancel` to cleanly exit Ralph mode.
