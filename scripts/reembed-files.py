#!/usr/bin/env python3
"""Re-embed Open WebUI files into pgvector.

Maintains a state file (reembed-state.json) tracking which files succeeded
or failed, so you can re-run to retry only the failures.

Usage:
    python3 scripts/reembed-files.py              # Process pending/failed files
    python3 scripts/reembed-files.py --reset      # Reset state and start fresh
    python3 scripts/reembed-files.py --status      # Show current status
"""

import json, urllib.request, os, time, sys, argparse

BASE = "https://openwebui.aws.genai.umbc.edu"
STATE_FILE = os.path.join(os.path.dirname(__file__), "reembed-state.json")
DELAY_BETWEEN_FILES = 8
RETRY_ATTEMPTS = 4


def get_headers():
    token = os.environ.get("OPENWEBUI_ADMIN_TOKEN")
    if not token:
        print("ERROR: OPENWEBUI_ADMIN_TOKEN environment variable not set")
        sys.exit(1)
    return {"Authorization": f"Bearer {token}", "Content-Type": "application/json"}


def load_state():
    if os.path.exists(STATE_FILE):
        with open(STATE_FILE) as f:
            return json.load(f)
    return {"succeeded": {}, "failed": {}, "skipped": {}}


def save_state(state):
    with open(STATE_FILE, "w") as f:
        json.dump(state, f, indent=2)


def fetch_all_files(headers):
    all_files = []
    page = 1
    while True:
        req = urllib.request.Request(f"{BASE}/api/v1/files/?page={page}", headers=headers)
        with urllib.request.urlopen(req) as resp:
            d = json.loads(resp.read())
        items = d.get("items", d) if isinstance(d, dict) else d
        if not items:
            break
        all_files.extend(items)
        total = d.get("total", len(all_files)) if isinstance(d, dict) else len(all_files)
        print(f"  Fetched page {page}: {len(all_files)}/{total} files")
        if len(all_files) >= total:
            break
        page += 1
    return all_files


def show_status(state):
    s = len(state["succeeded"])
    f = len(state["failed"])
    sk = len(state["skipped"])
    total = s + f + sk
    print(f"Re-embed status ({STATE_FILE}):")
    print(f"  Succeeded: {s}")
    print(f"  Failed:    {f}")
    print(f"  Skipped:   {sk} (no embeddable content)")
    if total:
        print(f"  Total:     {total}")
    if state["failed"]:
        print(f"\nFailed files:")
        for fid, info in list(state["failed"].items())[:20]:
            print(f"  - {info['filename']}: {info['error']}")
        if len(state["failed"]) > 20:
            print(f"  ... and {len(state['failed']) - 20} more")


def process_files(headers, state):
    print("Fetching file list...")
    all_files = fetch_all_files(headers)

    to_process = []
    for f in all_files:
        fid = f["id"]
        if fid in state["succeeded"]:
            continue
        data = f.get("data", {})
        content = data.get("content", "") if isinstance(data, dict) else ""
        if not content or not content.strip():
            state["skipped"][fid] = {"filename": f["filename"]}
            continue
        to_process.append(f)

    save_state(state)

    already_done = len(state["succeeded"])
    print(f"\n{len(to_process)} files to process ({already_done} already succeeded, {len(state['skipped'])} skipped)\n")

    if not to_process:
        print("Nothing to do!")
        return

    success = errors = 0
    for i, f in enumerate(to_process):
        fid = f["id"]
        fname = f["filename"][:60]
        coll = f.get("meta", {}).get("collection_name", f"file-{fid}")

        ok = False
        last_error = ""
        for attempt in range(RETRY_ATTEMPTS):
            payload = json.dumps({"file_id": fid, "collection_name": coll}).encode()
            req = urllib.request.Request(
                f"{BASE}/api/v1/retrieval/process/file",
                data=payload, headers=headers, method="POST"
            )
            try:
                with urllib.request.urlopen(req, timeout=180) as resp:
                    resp.read()
                ok = True
                break
            except Exception as e:
                code = getattr(e, "code", 0)
                last_error = f"{code}: {str(e)[:80]}"
                if code in (429, 502, 503, 504) and attempt < RETRY_ATTEMPTS - 1:
                    wait = 10 * (attempt + 1)
                    print(f"  [{i+1}/{len(to_process)}] {fname} - {code}, retry in {wait}s...")
                    time.sleep(wait)
                else:
                    break

        if ok:
            success += 1
            state["succeeded"][fid] = {"filename": f["filename"]}
            state["failed"].pop(fid, None)
            if (i + 1) % 10 == 0 or i == 0:
                print(f"  [{i+1}/{len(to_process)}] OK: {fname}  ({success} ok, {errors} fail)")
        else:
            errors += 1
            state["failed"][fid] = {"filename": f["filename"], "error": last_error}
            if (i + 1) % 10 == 0:
                print(f"  [{i+1}/{len(to_process)}] FAIL: {fname}  ({success} ok, {errors} fail)")

        if (i + 1) % 10 == 0:
            save_state(state)

        time.sleep(DELAY_BETWEEN_FILES)

    save_state(state)
    print(f"\nDone: {success} ok, {errors} failed this run")
    print(f"Cumulative: {len(state['succeeded'])} succeeded, {len(state['failed'])} failed, {len(state['skipped'])} skipped")


def main():
    parser = argparse.ArgumentParser(description="Re-embed Open WebUI files into pgvector")
    parser.add_argument("--reset", action="store_true", help="Reset state and start fresh")
    parser.add_argument("--status", action="store_true", help="Show current status")
    args = parser.parse_args()

    state = load_state()

    if args.reset:
        state = {"succeeded": {}, "failed": {}, "skipped": {}}
        save_state(state)
        print("State reset.")
        return

    if args.status:
        show_status(state)
        return

    headers = get_headers()
    process_files(headers, state)


if __name__ == "__main__":
    main()
