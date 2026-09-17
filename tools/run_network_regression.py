#!/usr/bin/env python3
"""Run real Godot peers with no SceneMultiplayer relay; no Steam accounts needed.

This tests the production spawn/state/RPC stack over localhost ENet, NOT Steam.
The last client joins late, then disconnects/reconnects with a fresh peer ID.
"""
import argparse
import pathlib
import subprocess
import time

parser = argparse.ArgumentParser()
parser.add_argument("--godot", default="godot")
parser.add_argument("--counts", type=int, nargs="+", default=[2, 3, 4])
args = parser.parse_args()
logs = pathlib.Path("build/verification/network_star")
logs.mkdir(parents=True, exist_ok=True)

for count in args.counts:
    if count < 2:
        raise SystemExit("At least two players required")
    processes = []
    handles = []
    try:
        for slot in range(count):
            if slot == count - 1:
                time.sleep(2.5)  # Existing state must be replayed to this late join.
            elif slot == 1:
                time.sleep(0.5)  # Remaining early clients then connect concurrently.
            path = logs / f"{count}_players_slot_{slot}.log"
            output = path.open("w")
            handles.append(output)
            processes.append(subprocess.Popen([
                args.godot, "--headless", "--path", ".",
                "res://scenes/tests/network_star_regression.tscn", "--",
                f"--slot={slot}", f"--count={count}", f"--port={29835 + count}",
            ], stdout=output, stderr=subprocess.STDOUT))
        deadline = time.monotonic() + 60
        while any(process.poll() is None for process in processes):
            if any(process.poll() not in (None, 0) for process in processes):
                break
            if time.monotonic() > deadline:
                break
            time.sleep(0.1)
    finally:
        for process in processes:
            if process.poll() is None:
                process.kill()
                process.wait()
        for output in handles:
            output.close()
    failed = False
    for slot, process in enumerate(processes):
        path = logs / f"{count}_players_slot_{slot}.log"
        text = path.read_text()
        # Godot can return zero even after a script reports an assertion failure.
        ok = process.returncode == 0 and "NETWORK_STAR_PASS" in text and "ERROR:" not in text
        print(f"{count} players, slot {slot}: {'PASS' if ok else 'FAIL'} ({path})")
        if not ok:
            print(text[-12000:])
            failed = True
    if failed:
        raise SystemExit(1)
