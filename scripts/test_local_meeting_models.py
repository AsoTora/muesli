#!/usr/bin/env python3
"""Test local audio import, meeting notes, and saved records with synthetic audio."""

import argparse
import json
from pathlib import Path
import subprocess
import tempfile
import time
import urllib.request


def run(command, output_dir, name):
    result = subprocess.run(command, capture_output=True, text=True, timeout=600)
    (output_dir / f"{name}.stdout.log").write_text(result.stdout)
    (output_dir / f"{name}.stderr.log").write_text(result.stderr)
    if result.returncode:
        raise RuntimeError(f"{name} failed. See {output_dir / (name + '.stderr.log')}")
    return result.stdout


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--cli", type=Path, default=Path("/Applications/Muesli.app/Contents/MacOS/muesli-cli"))
    parser.add_argument("--models", nargs="+", default=["qwen3.5:4b", "qwen3.5:9b", "gemma3:4b"])
    parser.add_argument("--output-dir", type=Path)
    args = parser.parse_args()
    output_dir = args.output_dir or Path(tempfile.mkdtemp(prefix="muesli-meeting-e2e-"))
    output_dir.mkdir(parents=True, exist_ok=True)
    print(f"Evidence directory: {output_dir}", flush=True)

    # Use the loopback server and an isolated support directory for each model.
    # No personal recording, configuration, or database enters this test.
    with urllib.request.urlopen("http://127.0.0.1:11434/api/tags", timeout=10) as response:
        installed = {model["name"] for model in json.load(response)["models"]}
    missing = set(args.models) - installed
    if missing:
        raise RuntimeError(f"Pull these Ollama models first: {', '.join(sorted(missing))}")

    fixture = (
        "This is a planning meeting. We agreed to ship the release on Friday. "
        "Alice will fix the meeting model selector by Thursday. "
        "Bob will validate microphone and system audio capture by Friday. "
        "We will keep transcription and meeting notes on this Mac. "
        "There are no budget changes."
    )
    (output_dir / "fixture.txt").write_text(fixture)
    run(["say", "-v", "Samantha", "-o", str(output_dir / "fixture.aiff"), fixture], output_dir, "speech")
    audio = output_dir / "fixture.wav"
    run(["afconvert", "-f", "WAVE", "-d", "LEI16@16000", str(output_dir / "fixture.aiff"), str(audio)], output_dir, "audio")

    results = []
    for index, model in enumerate(args.models):
        support = output_dir / f"model-{index}"
        support.mkdir(exist_ok=True)
        config = {"meeting_summary_backend": "ollama", "ollama_url": "http://127.0.0.1:11434", "ollama_model": model}
        (support / "config.json").write_text(json.dumps(config))
        output = support / "transcription.json"
        started = time.monotonic()
        run([
            str(args.cli), "transcribe", str(audio), "--support-dir", str(support),
            "--model", "parakeet-v3", "--format", "json", "--summarize", "--save-meeting",
            "--title", "Synthetic local meeting validation", "--output", str(output),
        ], support, "transcribe")
        payload = json.loads(output.read_text())
        if not payload.get("ok"):
            raise RuntimeError(f"{model}: transcription failed: {payload.get('error')}")
        data = payload["data"]
        if data["warnings"] or not data.get("summary"):
            raise RuntimeError(f"{model}: missing notes or warnings: {data['warnings']}")
        for field in ["transcript", "summary"]:
            if not all(word in data[field].lower() for word in ["alice", "bob", "friday"]):
                raise RuntimeError(f"{model}: {field} lost an owner or deadline. See {output}")
        meeting_id = data.get("savedMeetingID")
        if meeting_id is None:
            raise RuntimeError(f"{model}: meeting was not saved")
        record = json.loads(run([
            str(args.cli), "meetings", "get", str(meeting_id), "--support-dir", str(support),
        ], support, "meeting"))
        if not record.get("ok") or record["data"]["notesState"] != "structured_notes":
            raise RuntimeError(f"{model}: saved meeting does not have structured notes")
        if record["data"]["formattedNotes"] != data["summary"]:
            raise RuntimeError(f"{model}: saved notes differ from generated notes")
        if Path(record["meta"]["dbPath"]).resolve() != (support / "muesli.db").resolve():
            raise RuntimeError(f"{model}: CLI used a database outside the test directory")
        result = {"model": model, "passed": True, "seconds": round(time.monotonic() - started, 1), "meeting_id": meeting_id}
        results.append(result)
        (output_dir / "results.json").write_text(json.dumps(results, indent=2))
        print(json.dumps(result), flush=True)


if __name__ == "__main__":
    main()
