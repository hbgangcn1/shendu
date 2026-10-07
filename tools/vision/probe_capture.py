"""Probe which Godot launch mode yields real (non-black) viewport pixels.

Procedure per mode: launch game with `-- --qa-auto-run --run-id=probe`,
wait ~6s, write {"action":"capture","path":"..."} to res://.agent_input.json
(socket polls every 100ms), poll up to 10s for the PNG.
PASS = PNG exists, >1024 bytes, and NO `.black` marker sibling.
Fallback (if the vision-prep .black-marker edit is absent): reject files
under 1024 bytes or with fully uniform pixels (stdlib PNG decode, no deps).

Usage:
    python probe_capture.py [--mode windowed]
Modes: windowed (plain), headless (expected FAIL reference, optional)
"""
import json
import os
import struct
import subprocess
import sys
import time
import zlib

PROJECT_DIR = r"C:\Users\hbgan\Projects\shendu"
GODOT_BIN = r"C:\Tools\Godot\Godot_v4.7-stable_win64.exe"
INPUT_FILE = os.path.join(PROJECT_DIR, ".agent_input.json")
OUT_DIR = os.path.join(PROJECT_DIR, "tools", "vision")
MIN_BYTES = 1024


def launch_game(extra_args: list[str]) -> subprocess.Popen:
    args = [GODOT_BIN, "--path", PROJECT_DIR] + extra_args + [
        "--", "--qa-auto-run", "--run-id=probe",
    ]
    print(f"launch: {' '.join(args)}", flush=True)
    return subprocess.Popen(args, cwd=PROJECT_DIR,
                            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def request_capture(png_abs: str) -> None:
    res_path = "res://" + os.path.relpath(png_abs, PROJECT_DIR).replace(os.sep, "/")
    with open(INPUT_FILE, "w", encoding="utf-8") as f:
        json.dump({"action": "capture", "path": res_path}, f)
    print(f"wrote capture cmd -> {res_path}", flush=True)


def wait_for_file(path: str, timeout_s: float) -> bool:
    deadline = time.time() + timeout_s
    while time.time() < deadline:
        if os.path.exists(path) and os.path.getsize(path) > 0:
            return True
        time.sleep(0.25)
    return os.path.exists(path)


def is_uniform_png(path: str) -> bool | None:
    """True if every pixel identical, False if varied, None if undecodable."""
    try:
        with open(path, "rb") as f:
            data = f.read()
        assert data[:8] == b"\x89PNG\r\n\x1a\n"
        pos, w, h, bitd, ctype = 8, 0, 0, 0, 0
        raw = b""
        while pos < len(data):
            (ln,) = struct.unpack(">I", data[pos:pos + 4])
            typ = data[pos + 4:pos + 8]
            chunk = data[pos + 8:pos + 8 + ln]
            if typ == b"IHDR":
                w, h, bitd, ctype = struct.unpack(">IIBB", chunk[:10])
            elif typ == b"IDAT":
                raw += chunk
            pos += 12 + ln
        if w == 0 or h == 0 or bitd != 8 or ctype not in (2, 6):
            return None  # unsupported layout -> unknown
        ch = {2: 3, 6: 4}[ctype]
        px = zlib.decompress(raw)
        stride = w * ch
        out = bytearray()
        prev = bytearray(stride)
        p = 0
        for row in range(h):
            flt = px[p]; p += 1
            line = bytearray(px[p:p + stride]); p += stride
            if flt == 1:
                for i in range(ch, stride):
                    line[i] = (line[i] + line[i - ch]) & 255
            elif flt == 2:
                for i in range(stride):
                    line[i] = (line[i] + prev[i]) & 255
            elif flt == 3:
                for i in range(stride):
                    a = line[i - ch] if i >= ch else 0
                    line[i] = (line[i] + ((a + prev[i]) >> 1)) & 255
            elif flt == 4:
                for i in range(stride):
                    a = line[i - ch] if i >= ch else 0
                    b = prev[i]
                    c = prev[i - ch] if i >= ch else 0
                    pa, pb, pc = abs(b - c), abs(a - c), abs(a + b - 2 * c)
                    pr = a if (pa <= pb and pa <= pc) else (b if pb <= pc else c)
                    line[i] = (line[i] + pr) & 255
            elif flt != 0:
                return None
            out += line
            prev = line
        first = bytes(out[:ch])
        return all(bytes(out[i:i + ch]) == first for i in range(0, len(out), ch))
    except Exception as e:
        print(f"uniform check undecodable: {e}", flush=True)
        return None


def verdict(png_abs: str) -> tuple[str, dict]:
    info: dict = {"path": png_abs, "exists": os.path.exists(png_abs),
                  "bytes": os.path.getsize(png_abs) if os.path.exists(png_abs) else 0,
                  "black_marker": os.path.exists(png_abs + ".black")}
    marker_supported = True  # qa_capture.gd writes .black on placeholder path
    if not info["exists"]:
        return "FAIL", info
    if info["bytes"] <= MIN_BYTES:
        return "FAIL", {**info, "reason": f"<= {MIN_BYTES} bytes"}
    if info["black_marker"]:
        return "FAIL", {**info, "reason": ".black marker present (placeholder)"}
    if not marker_supported:
        uni = is_uniform_png(png_abs)
        info["uniform"] = uni
        info["fallback_note"] = "marker edit absent; used size+uniform fallback"
        if uni is True:
            return "FAIL", {**info, "reason": "fully uniform pixels"}
    else:
        uni = is_uniform_png(png_abs)
        info["uniform"] = uni  # informational only; marker is authoritative
    return "PASS", info


def kill_all_godot() -> bool:
    subprocess.run(["taskkill", "/F", "/IM",
                    os.path.basename(GODOT_BIN)], capture_output=True)
    time.sleep(1)
    r = subprocess.run(["tasklist", "/FI", "IMAGENAME eq "
                        + os.path.basename(GODOT_BIN)], capture_output=True, text=True)
    clean = os.path.basename(GODOT_BIN).lower() not in r.stdout.lower()
    print(f"cleanup: {'no Godot process remains' if clean else r.stdout}", flush=True)
    return clean


MODES: dict[str, list[str]] = {
    "windowed": [],  # plain windowed mode
    "headless": ["--headless"],  # reference: dummy renderer, expect FAIL
    # windowed via tools/vision/godot_launch.gd: mounts QA nodes deferred
    # (plain launch mounts zero -> AgentSocket never polls). Same game
    # viewport, same socket capture protocol, real renderer.
    "windowed-helper": ["-s", "res://tools/vision/godot_launch.gd"],
}


def run_mode(mode: str) -> tuple[str, dict]:
    png_abs = os.path.join(OUT_DIR, f"probe_{mode}.png")
    for stale in (png_abs, png_abs + ".black", INPUT_FILE):
        try:
            os.remove(stale)
        except OSError:
            pass
    proc = launch_game(MODES[mode])
    try:
        time.sleep(6)
        if proc.poll() is not None:
            return "FAIL", {"path": png_abs, "reason": f"exited early rc={proc.returncode}"}
        request_capture(png_abs)
        found = wait_for_file(png_abs, 10)
        if not found:
            return "FAIL", {"path": png_abs, "exists": False,
                            "reason": "no PNG within 10s"}
        time.sleep(0.5)  # let the write finish
        return verdict(png_abs)
    finally:
        try:
            with open(INPUT_FILE, "w", encoding="utf-8") as f:
                json.dump({"action": "quit"}, f)
            time.sleep(1)
        except OSError:
            pass
        if proc.poll() is None:
            proc.kill()
        kill_all_godot()
        try:
            os.remove(INPUT_FILE)
        except OSError:
            pass


def main() -> int:
    modes = sys.argv[1:] if len(sys.argv) > 1 else ["windowed"]
    modes = [m.lstrip("-") for m in modes]
    results = {}
    for m in modes:
        if m not in MODES:
            print(f"unknown mode {m}, known: {list(MODES)}")
            continue
        v, info = run_mode(m)
        results[m] = (v, info)
        print(f"MODE {m}: {v} {json.dumps(info)}", flush=True)
    clean = kill_all_godot()
    print(f"final cleanup clean={clean}", flush=True)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
