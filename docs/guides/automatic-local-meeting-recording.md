# Automatic local meeting recording

This fork can detect attended calls in Chrome, Firefox, and Microsoft Teams, start recording without a notification click, transcribe on the Mac, and generate the final title and notes with a local Gemma model.

Nothing is uploaded when **Local Gemma preset** is enabled. That mode accepts only `localhost`, `127.0.0.1`, or `::1`, refuses redirects to another host, and never falls back to OpenAI, ChatGPT, OpenRouter, or another cloud provider.

> Recording laws and workplace policies vary. Tell participants when required, respect consent, and do not enable automatic recording where your organization forbids it.

## Requirements

- Apple Silicon Mac
- macOS 14.2 or newer
- Xcode 16 or newer when building from source
- Ollama (simplest) or a recent llama.cpp build
- Enough free space for the speech-to-text model, Gemma model, transcripts, and any retained audio

## Build and install the fork

```bash
git clone https://github.com/AsoTora/muesli.git
cd muesli
git switch andreishvedau/auto-meeting-recorder
MUESLI_SKIP_SIGN=1 ./scripts/dev-test.sh --lane A
```

The development build is installed as `/Applications/MuesliDevA.app`. It uses a separate bundle ID and does not modify production Muesli data. Re-run the final command after pulling changes.

For a release-style local build, use `./scripts/build_native_app.sh` only when the required signing identity is available.

## Grant macOS permissions

Open **System Settings → Privacy & Security** and grant the installed Muesli build:

- **Microphone** — records your voice.
- **Screen & System Audio Recording** — records the remote side of browser and Teams calls.
- **Accessibility** — reads the active meeting URL/window evidence and supports Muesli's dictation UI.
- **Input Monitoring** — supports global shortcuts.
- **Camera** when prompted — Muesli observes camera activity as one meeting-attendance signal; it does not record camera video.
- **Calendars** only if scheduled meeting integration is wanted.

Quit and reopen Muesli after changing permissions. Each development lane has a distinct identity, so permissions granted to `MuesliDevA` do not automatically apply to `MuesliDevB` or production `Muesli`.

## Configure local transcription and auto-recording

1. Open Muesli **Settings → Models** and install a local speech-to-text model. Parakeet is a good fast default; Whisper remains available.
2. Open **Settings → Meetings**.
3. Enable **Auto-record detected calls**. This is separate from scheduled-calendar auto-recording.
4. Leave the persistent recording indicator enabled so recording is always visible.
5. Choose the desired recording retention policy. Transcripts and notes can be retained without keeping raw audio.

A candidate must remain stable for three seconds. A browser process merely being open is not enough: Muesli requires meeting URL plus attendance/input evidence. Native Teams similarly requires attributed active-call audio/input evidence. One continuous call starts at most one recording; a failed start waits 30 seconds before retrying.

If meeting evidence disappears temporarily, Muesli shows the existing stop warning and waits through its grace period. Evidence recovery cancels the stop. Continued loss stops and finalizes the meeting automatically.

## Recommended: Ollama with Gemma

Install and prepare the model:

```bash
brew install ollama
ollama serve
```

In another terminal:

```bash
ollama pull gemma3:4b
ollama list
curl http://127.0.0.1:11434/api/tags
```

Then open **Settings → Meetings → Meeting Summaries** and choose:

- **Local Gemma preset:** `Ollama · Gemma 3 4B`
- **Ollama URL:** `http://localhost:11434`
- **Model:** `gemma3:4b`

The preset is explicit: generic Ollama users keep their existing model and URL until they select it. After an automatically recorded call stops, both title generation and structured meeting notes use this Ollama model.

## Alternative: llama.cpp with a Gemma GGUF

Install llama.cpp and obtain a Gemma instruction-tuned GGUF compatible with your llama.cpp version. The model file is not bundled with Muesli.

```bash
brew install llama.cpp
mkdir -p "$HOME/Models"
```

Place the GGUF under `$HOME/Models`, then start a loopback-only server. Replace the example filename with the actual downloaded file:

```bash
llama-server \
  --model "$HOME/Models/gemma-3-4b-it-Q4_K_M.gguf" \
  --alias gemma-local \
  --host 127.0.0.1 \
  --port 8080
```

Verify the OpenAI-compatible API:

```bash
curl http://127.0.0.1:8080/v1/models
```

In Muesli choose:

- **Local Gemma preset:** `llama.cpp · Gemma`
- **API format:** `OpenAI-compatible`
- **Endpoint:** `http://127.0.0.1:8080/v1`
- **Model:** `gemma-local` (must match `--alias`)
- **API key:** blank

Do not bind llama-server to `0.0.0.0` for this workflow. The local preset deliberately rejects LAN and internet hosts.

## Platform smoke checks

Run these after granting permissions. A code build or unit-test pass is not proof of a live browser/Teams recording.

| Platform | Test | Expected evidence |
| --- | --- | --- |
| Chrome | Join a Google Meet, speak, and play remote audio | Recording starts after about 3 seconds; indicator appears; transcript contains **You** and remote audio |
| Firefox | Join Google Meet or Teams Web | Same as Chrome; Firefox is attributed as the source rather than detected from process presence |
| Microsoft Teams | Join a native Teams call | Both `com.microsoft.teams2` and legacy `com.microsoft.teams` are recognized; mic and remote audio are captured |

For each platform also verify:

1. Briefly switch away or interrupt one signal; recording should survive the grace period.
2. Leave the call; warning appears and recording stops automatically after continued signal loss.
3. Open the completed meeting; title and summary should be present.
4. Stop Ollama or llama-server and repeat with a short test call; Muesli should preserve the transcript and show actionable local-runtime remediation, not contact a cloud backend.

## Data and privacy

Production data is stored under:

```text
~/Library/Application Support/Muesli/config.json
~/Library/Application Support/Muesli/muesli.db
~/Library/Application Support/Muesli/meetings/
```

Development lanes use `MuesliDev`, `MuesliDevA`, `MuesliDevB`, or `MuesliDevC` in place of `Muesli`. Shared speech models normally live under:

```text
~/Library/Application Support/FluidAudio/Models/
~/.cache/muesli/models/
```

Ollama manages its own model storage. Muesli's config is written with owner-only permissions. Text may sync through iCloud only if Muesli's iCloud sync is enabled; raw meeting audio is not iCloud-synced. Disable iCloud sync if the desired boundary is strictly this Mac.

Choose an audio retention policy appropriate for the meeting sensitivity. Deleting a meeting from the UI should be paired with checking any exported Markdown/PDF and retained recording files.

## Troubleshooting

### A call is not detected

- Confirm **Auto-record detected calls** is enabled, not only calendar auto-record.
- Keep the meeting tab/window active long enough to establish the three-second candidate.
- Check Accessibility permission and restart Muesli.
- Confirm the app is not muted in meeting-detection settings.
- Firefox must expose the active tab URL through Accessibility; update Firefox and re-check permission if it does not.
- Process presence alone intentionally does not trigger recording.

### The remote side is missing

- Grant **Screen & System Audio Recording**, then restart Muesli.
- Check that the expected Chrome, Firefox, or Teams process is producing audio.
- Avoid changing the audio device during the first seconds of the recording.
- Bluetooth and AirPods may take a moment to settle; test once with built-in speakers/microphone to isolate routing.

### Ollama is unreachable

```bash
ollama serve
curl http://127.0.0.1:11434/api/tags
```

If the port is already in use, find the existing Ollama process rather than starting a second server.

### Gemma is missing

```bash
ollama pull gemma3:4b
ollama list
```

The model name in Muesli must exactly match Ollama's tag.

### llama.cpp returns model-not-found

Start `llama-server` with `--alias gemma-local` and enter `gemma-local` in Muesli. Confirm `curl http://127.0.0.1:8080/v1/models` returns that ID.

### Local-only validation rejects the URL

Use only `localhost`, `127.0.0.1`, or `::1`. Hostnames such as `localhost.example.com`, LAN IPs, and redirects to non-loopback hosts are rejected intentionally.

### Summary fails after a long call

- Confirm the runtime is still running and has enough memory.
- Use a smaller/quantized Gemma model when memory pressure is high.
- Keep the transcript: Muesli stores a summary-failure note plus raw transcript when structured note generation fails.
- Start the runtime, then use **Re-summarize** on the saved meeting.

### Recording stops too soon or never stops

- A transient loss should recover during the visible grace period.
- If it stops too soon, inspect whether browser/Teams audio input and meeting URL evidence both disappeared.
- If it never stops, fully leave the call rather than leaving a joined background tab or Teams call window active.

