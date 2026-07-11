# Automatic Local Meeting Recorder Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Automatically record every detected call the user attends in Chrome, Firefox, or native Microsoft Teams, transcribe it locally, and create a local Gemma summary without requiring a notification click.

**Architecture:** Extend the existing stabilized `MeetingCandidate` activity stream with a deterministic auto-record policy that debounces appearance, deduplicates start attempts, and invokes the existing microphone plus process/system-audio recording pipeline. Reuse `MeetingAutoStopTracker` for signal-loss warning/stop behavior and reuse the local Ollama/custom OpenAI-compatible summary clients with explicit local Gemma UX and strict no-cloud-fallback validation.

**Tech Stack:** Swift 6, SwiftUI, Swift Testing, macOS Core Audio process taps and ScreenCaptureKit fallback, local ASR, Ollama or llama.cpp OpenAI-compatible HTTP API.

---

## File Structure

- `native/MuesliNative/Sources/MuesliNativeApp/MeetingCandidateResolver.swift`: Firefox support and browser/Teams candidate attribution.
- `native/MuesliNative/Sources/MuesliNativeApp/BrowserMeetingActivityCollector.swift`: Firefox meeting-URL collection.
- `native/MuesliNative/Sources/MuesliNativeApp/MeetingAutoRecordPolicy.swift`: pure debounce/dedup/retry state machine.
- `native/MuesliNative/Sources/MuesliNativeApp/MuesliController.swift`: connect candidates to existing record/auto-stop flow.
- `native/MuesliNative/Sources/MuesliNativeApp/DetectedMeetingAutoRecordCoordinator.swift`: controller-testable seam from stable candidate through exactly-once start/failure/stop finalization.
- `native/MuesliNative/Sources/MuesliNativeApp/Models.swift`: persist detected-call and local Gemma settings.
- `native/MuesliNative/Sources/MuesliNativeApp/SettingsView.swift`: controls for auto-record and Gemma.
- `native/MuesliNative/Sources/MuesliNativeApp/MeetingSummaryClient.swift`: strict local routing and actionable errors.
- `native/MuesliNative/Tests/MuesliTests/{MeetingCandidateResolverTests,BrowserMeetingActivityCollectorTests,MeetingAutoRecordPolicyTests,MeetingAutoStopPolicyTests,MeetingSummaryClientTests,ModelsTests}.swift`: behavior coverage.
- `docs/guides/automatic-local-meeting-recording.md`: setup, use, verification, privacy, troubleshooting.

## Acceptance Criteria

- With detected-call auto-record enabled, an attended-call candidate from Chrome, Firefox, or native Teams starts after a 3-second stable window without a notification click.
- Candidate evidence must show actual attendance (meeting URL plus foreground/input activity, or attributed Teams input/full-duplex activity); process presence alone never starts a recording.
- One continuous `suppressionID` creates at most one meeting despite focus, URL, helper PID, or evidence changes. Failed starts use a 30-second retry cooldown.
- The existing meeting pipeline captures mic and source process/system audio, displays persistent recording state, and transcribes locally.
- Existing `autoRecordMeetings` remains calendar-only and backward compatible; a separate setting controls detected calls.
- Firefox `org.mozilla.firefox` works for Google Meet and Teams Web resolution, browser audio attribution, and app muting.
- Native Teams supports `com.microsoft.teams2` and `com.microsoft.teams`.
- Candidate loss uses the existing grace period and visible warning, then automatic stop; recovered transient loss does not stop.
- Stopping an automatically detected recording runs normal finalization and automatically generates its summary and title with the selected local Gemma backend; this is covered end-to-end through a controller-level seam.
- The local Gemma preset routes only to Ollama or llama.cpp's OpenAI-compatible loopback endpoint (`localhost`, `127.0.0.1`, or `::1`). It rejects non-loopback URLs and redirects that leave loopback, never falls back to OpenAI, ChatGPT, OpenRouter, or another cloud backend, and fails closed for unknown backends.
- Generic Ollama/custom configuration remains unchanged; choosing the Gemma preset explicitly selects `gemma3:4b` without migrating existing Ollama users.
- Missing runtime, unreachable endpoint, or absent model gives actionable endpoint/model/setup remediation.
- The guide documents macOS permissions, exact runtime commands, settings, three-platform smoke tests, data locations, consent/privacy, and troubleshooting.
- Targeted tests, full native tests, and native debug build pass.

### Task 1: Establish Fork and Branch

**Files:** None.

- [x] **Step 1: Clone upstream and preserve history**

Run: `git clone https://github.com/Muesli-HQ/muesli.git /Users/asotora/Projects/muesli`
Expected: clean `main` at `9b8e75ad` or newer.

- [x] **Step 2: Configure remotes and branch**

Run: `git remote rename origin upstream && git remote add origin https://github.com/AsoTora/muesli.git && git switch -c andreishvedau/auto-meeting-recorder`
Expected: clean requested branch; correct `origin`/`upstream`.

- [ ] **Step 3: Create/verify GitHub fork after AsoTora authentication is refreshed**

Run: `gh auth switch --user AsoTora && gh repo fork Muesli-HQ/muesli --clone=false --remote=false`
Expected: `gh repo view AsoTora/muesli --json isFork,parent` identifies `Muesli-HQ/muesli` as parent.

### Task 2: Recognize Firefox Meeting Activity

**Files:**
- Modify: `native/MuesliNative/Sources/MuesliNativeApp/MeetingCandidateResolver.swift`
- Modify: `native/MuesliNative/Sources/MuesliNativeApp/BrowserMeetingActivityCollector.swift`
- Modify: every bundle-ID allowlist found by `rg -n 'browserApps|browserBundleIDs|supported.*browser|muted.*Bundle|audio.*bundle' native/MuesliNative/Sources native/MuesliNative/Tests`
- Test: `native/MuesliNative/Tests/MuesliTests/MeetingCandidateResolverTests.swift`
- Test: `native/MuesliNative/Tests/MuesliTests/BrowserMeetingActivityCollectorTests.swift`

- [ ] **Step 1: Write failing tests** for `browserApps["org.mozilla.firefox"]`, Firefox Meet URL plus input attribution, Firefox audio-session fallback, and URL collection.
- [ ] **Step 2: Verify red** with `swift test --package-path native/MuesliNative --scratch-path /tmp/muesli-auto-meeting-recorder-spm --filter 'MeetingCandidateResolverTests|BrowserMeetingActivityCollectorTests'`; expect Firefox assertions to fail.
- [ ] **Step 3: Audit all bundle-ID gates** with `rg -n 'browserApps|browserBundleIDs|supported.*browser|muted.*Bundle|audio.*bundle' native/MuesliNative/Sources native/MuesliNative/Tests`; add Firefox to resolver, collector, audio attribution, and mute/exclusion paths where those paths do not derive from `browserApps`.
- [ ] **Step 4: Implement minimal support** by adding Firefox to the authoritative allowlist(s); keep `AXDocument` primary and add a Firefox-specific active-tab fallback only if test/live evidence proves necessary. Never detect from process presence alone.
- [ ] **Step 5: Verify green** with the same command; expect PASS, including audio attribution and mute/exclusion assertions.
- [ ] **Step 6: Commit** with `git commit -m "feat: detect Firefox meeting activity"`.

### Task 3: Define Automatic Start Policy

**Files:**
- Create: `native/MuesliNative/Sources/MuesliNativeApp/MeetingAutoRecordPolicy.swift`
- Create: `native/MuesliNative/Tests/MuesliTests/MeetingAutoRecordPolicyTests.swift`

- [ ] **Step 1: Write failing pure-policy tests** for 3-second stability, `suppressionID` dedup, URL-to-audio identity changes, nil/reset behavior, new post-stop sessions, 30-second failed-start cooldown, and disabled-state reset.
- [ ] **Step 2: Verify red** with `swift test --package-path native/MuesliNative --scratch-path /tmp/muesli-auto-meeting-recorder-spm --filter MeetingAutoRecordPolicyTests`; expect missing type failure.
- [ ] **Step 3: Implement minimal state machine** returning `.none` or `.start(candidate)` from candidate/time/enabled/recording/starting input, plus explicit start-success, start-failure, and stop transitions.
- [ ] **Step 4: Verify green** with the same command; expect PASS.
- [ ] **Step 5: Commit** with `git commit -m "feat: add detected meeting auto-record policy"`.

### Task 4: Wire Auto-Start to Existing Recorder and Auto-Stop

**Files:**
- Modify: `native/MuesliNative/Sources/MuesliNativeApp/Models.swift`
- Modify: `native/MuesliNative/Sources/MuesliNativeApp/MuesliController.swift`
- Create: `native/MuesliNative/Sources/MuesliNativeApp/DetectedMeetingAutoRecordCoordinator.swift`
- Modify: `native/MuesliNative/Sources/MuesliNativeApp/SettingsView.swift`
- Test: `native/MuesliNative/Tests/MuesliTests/ModelsTests.swift`
- Test: `native/MuesliNative/Tests/MuesliTests/MeetingAutoRecordPolicyTests.swift`
- Create: `native/MuesliNative/Tests/MuesliTests/DetectedMeetingAutoRecordCoordinatorTests.swift`

- [ ] **Step 1: Write failing config tests** proving `autoRecordDetectedMeetings` defaults false, round-trips, and decodes old JSON.
- [ ] **Step 2: Verify red** with `swift test --package-path native/MuesliNative --scratch-path /tmp/muesli-auto-meeting-recorder-spm --filter ModelsTests`.
- [ ] **Step 3: Add persistence/UI** with a separate "Auto-record detected calls" switch and Chrome/Firefox/Teams description; keep notification preference independent.
- [ ] **Step 4: Add a controller-level coordinator seam** whose injected closures start recording and finalize/stop it. Write tests proving stable candidate -> exactly one start with title/source/origin; failed start -> policy cooldown; stop -> the normal finalization callback that requests local summary and title generation.
- [ ] **Step 5: Wire controller** through that seam from `handleMeetingActivityCandidate`; call `startForegroundMeetingRecording` using `MeetingAutoStopSource(candidate:)`, `.detectedAutoRecord`, and `.autoStopAfterWarning`; report success/failure to policy and `meetingMonitor`. Run detector whenever detected auto-record is enabled, even if notifications are disabled. Muted candidates remain excluded.
- [ ] **Step 6: Verify start/stop contract** with `swift test --package-path native/MuesliNative --scratch-path /tmp/muesli-auto-meeting-recorder-spm --filter 'DetectedMeetingAutoRecordCoordinatorTests|MeetingAutoRecordPolicyTests|MeetingAutoStopPolicyTests|ModelsTests'`; expect PASS.
- [ ] **Step 7: Commit** with `git commit -m "feat: auto-start detected meeting recordings"`.

### Task 5: Add Strict Local Gemma Summary UX

**Files:**
- Modify: `native/MuesliNative/Sources/MuesliNativeApp/Models.swift`
- Modify: `native/MuesliNative/Sources/MuesliNativeApp/SettingsView.swift`
- Modify: `native/MuesliNative/Sources/MuesliNativeApp/MeetingSummaryClient.swift`
- Test: `native/MuesliNative/Tests/MuesliTests/MeetingSummaryClientTests.swift`
- Test: `native/MuesliNative/Tests/MuesliTests/ModelsTests.swift`

- [ ] **Step 1: Write failing tests**: choosing the Gemma preset explicitly selects `gemma3:4b` without changing generic Ollama defaults/user config; only loopback hosts are accepted; cross-host redirects are rejected; missing runtime/model gives `ollama serve`/`ollama pull gemma3:4b` remediation; llama.cpp uses local custom OpenAI-compatible endpoint; unknown backend fails closed rather than defaulting to OpenAI; final summary and title generation both use the selected local backend.
- [ ] **Step 2: Verify red** with `swift test --package-path native/MuesliNative --scratch-path /tmp/muesli-auto-meeting-recorder-spm --filter 'MeetingSummaryClientTests|ModelsTests'`.
- [ ] **Step 3: Implement explicit local presets** while preserving generic Ollama/custom routes; validate loopback host and redirect destinations; never catch local errors and retry a cloud backend.
- [ ] **Step 4: Verify green** with the same command; expect PASS.
- [ ] **Step 5: Commit** with `git commit -m "feat: add local Gemma meeting summaries"`.

### Task 6: Write User Guide

**Files:**
- Create: `docs/guides/automatic-local-meeting-recording.md`
- Modify: `README.md`

- [ ] **Step 1: Document install/use** including build, Microphone/Screen Recording/Accessibility/Automation permissions, ASR, toggles, visible indicator, stop behavior, data/export locations.
- [ ] **Step 2: Document exact Gemma setup** including `ollama serve`, `ollama pull gemma3:4b`, and a tested llama.cpp command binding `--host 127.0.0.1`, using the `/v1` OpenAI-compatible base URL and the exact model ID entered in Muesli. State that the user must supply a compatible Gemma GGUF.
- [ ] **Step 3: Add smoke matrix/troubleshooting** for Chrome Meet, Firefox Meet/Teams Web, native Teams; cover permissions, no candidate, no system audio, unreachable runtime, missing model, recovered/expired auto-stop; state consent/policy responsibility.
- [ ] **Step 4: Link from README and commit** with `git commit -m "docs: add automatic local meeting recording guide"`.

### Task 7: Verification and Cross-Review

**Files:** Modify only files required by failures/findings.

- [ ] **Step 1: Run targeted suites** with `swift test --package-path native/MuesliNative --scratch-path /tmp/muesli-auto-meeting-recorder-spm --filter 'MeetingCandidateResolverTests|BrowserMeetingActivityCollectorTests|MeetingAutoRecordPolicyTests|DetectedMeetingAutoRecordCoordinatorTests|MeetingAutoStopPolicyTests|MeetingSummaryClientTests|ModelsTests'`; expect zero failures.
- [ ] **Step 2: Run full suite** with `swift test --package-path native/MuesliNative --scratch-path /tmp/muesli-auto-meeting-recorder-spm`; expect zero failures.
- [ ] **Step 3: Inspect build script usage, then build app** with the supported debug/development command reported by `./scripts/build_native_app.sh --help` or script source; expect successful app bundle.
- [ ] **Step 4: Static privacy audit** with `rg -n 'autoRecordDetectedMeetings|detectedAutoRecord|gemma|ollama|customLLM' native/MuesliNative/Sources docs/guides/automatic-local-meeting-recording.md`; confirm no Gemma cloud fallback.
- [ ] **Step 5: Cross-review**: Luna reviews Terra auto-record changes and Terra reviews Luna Gemma/docs changes; resolve findings and rerun affected checks.
- [ ] **Step 6: Run manual live-call smoke checks where permissions/accounts permit** for Chrome Meet, Firefox Meet/Teams Web, and native Teams: observe auto-start, persistent recording indicator, mic plus remote audio in transcript, recovery grace, automatic stop, and automatic local Gemma title/summary. Record each platform as PASS or explicitly UNVERIFIED; unit/build proof must not be presented as live-call proof.
- [ ] **Step 7: Package without premature push** using `git status --short && git log --oneline upstream/main..HEAD && git remote -v`; expect clean intentional commits and correct remotes.
