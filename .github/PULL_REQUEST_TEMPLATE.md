## Description
<!-- Provide a brief description of the changes introduced by this pull request. -->

## Pre-Merge Governance Checklist

### 1. Zero-Betting Policy Guard
- [ ] No betting/gambling terminology introduced (odds, spreads, moneyline, books, staking, Kelly, sportsbook).
- [ ] Win probabilities and simulation analytics conform strictly to open-data front-office principles.

### 2. Clean Git Status & Working Tree Hygiene
- [ ] Working tree is clean (git status shows no untracked or modified artifacts).
- [ ] No cache files, credentials, or ephemeral data checked in.
- [ ] Verified branch target is main.

### 3. Seven Publish Gate Assertions (tools/publish_web.R)
- [ ] **Assertion A (mtime freshness):** All declared web data payloads refreshed after run start.
- [ ] **Assertion B (slate agreement):** Season game counts and active slates agree with upstream schedule.
- [ ] **Assertion C (non-empty diff):** Real pending changes exist under web data tree before publish.
- [ ] **Assertion D (warning scan):** Exporter log contains no unresolved fatal errors or stage warnings.
- [ ] **Assertion E (publish branch):** HEAD is on deploy-tracked main branch.
- [ ] **Assertion F (payload provenance):** Payload embedded generated_at matches current pipeline run timestamp.
- [ ] **Assertion G (web dataset contracts):** Web test suite / contracts pass cleanly against uncommitted payloads.

### 4. Build & Typecheck Verification
- [ ] 	sc --noEmit passes with 0 type errors.
- [ ] Next.js static build (
pm run build) completes cleanly if frontend was touched.