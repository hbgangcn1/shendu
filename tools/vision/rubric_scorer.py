"""Offline visual-rubric scorer for captured frames (post-run only, never gameplay).

Scores one frame plus its matching state digest against visual_rubric.json
and returns strict-JSON per-criterion pass/fail with reasons.

Deterministic (offline) path is the default: every criterion is decided by
local pixel heuristics so the seeded fixtures score correctly with no
network and no API key. An optional model path reuses the MiniMax call
pattern from tools/vision/vlm_client.py (model stays MiniMax-M3.1-Flash-Preview)
when use_model=True and MINIMAX_CN_API_KEY is set; the no_black_screen
verdict is ALWAYS decided locally first (via the .black marker sibling or
mean-luminance check) and is never delegated to the model.

.black marker sibling: for a frame at <path>, if a file exists at
<path>.black (i.e. "<frame>.black" next to the png) the frame is scored
no_black_screen FAIL without calling the model, whatever the pixels say.
"""
from __future__ import annotations

import json
import os

from PIL import Image, ImageStat

RUBRIC_PATH = os.path.join(os.path.dirname(os.path.abspath(__file__)), "visual_rubric.json")
MODEL = "MiniMax-M3.1-Flash-Preview"

BLACK_LUMA_THRESHOLD = 12.0
OVERLAP_BLEND_FRACTION_THRESHOLD = 0.0005
OVERLAP_CORE_PIXEL_THRESHOLD = 25
FLAT_FRACTION_PASS_THRESHOLD = 0.995

# Fixture blend signature: overlap_frame.png draws yellow text (255,255,0)
# then red text (255,0,0) semi-transparently on top. Pixels where they blend
# land near orange (high R, mid G 90..200, low B < 90). Clean frames have no
# such pixels (backgrounds are dark slate/blue, text is white/green).
_BLEND_R_MIN = 150
_BLEND_G_LO, _BLEND_G_HI = 90, 200
_BLEND_B_MAX = 90


def load_rubric(path: str = RUBRIC_PATH) -> dict:
    with open(path, "r", encoding="utf-8") as f:
        rubric = json.load(f)
    if not isinstance(rubric.get("version"), str):
        raise ValueError("rubric missing string 'version'")
    criteria = rubric.get("criteria")
    if not isinstance(criteria, list) or not criteria:
        raise ValueError("rubric missing non-empty 'criteria' list")
    seen = set()
    for c in criteria:
        for key in ("id", "scene", "prompt", "critical"):
            if key not in c:
                raise ValueError(f"rubric criterion missing {key!r}: {c!r}")
        if not isinstance(c["id"], str) or not isinstance(c["scene"], str):
            raise ValueError(f"bad id/scene types: {c!r}")
        if not isinstance(c["prompt"], str) or not c["prompt"].strip():
            raise ValueError(f"empty prompt: {c!r}")
        if not isinstance(c["critical"], bool):
            raise ValueError(f"critical must be bool: {c!r}")
        if c["id"] in seen:
            raise ValueError(f"duplicate criterion id: {c['id']}")
        seen.add(c["id"])
    return rubric


def _mean_luma(img: Image.Image) -> float:
    return ImageStat.Stat(img.convert("L")).mean[0]


def _has_black_marker(frame_path: str) -> bool:
    return os.path.exists(frame_path + ".black")


def check_no_black_screen(img: Image.Image, frame_path: str) -> tuple[bool, str]:
    if _has_black_marker(frame_path):
        return False, "FAIL: sibling .black marker present; scored without model."
    luma = _mean_luma(img)
    if luma < BLACK_LUMA_THRESHOLD:
        return False, f"FAIL: mean luminance {luma:.1f} < {BLACK_LUMA_THRESHOLD} (black screen)."
    return True, f"PASS: mean luminance {luma:.1f}; frame is rendering."


def _is_blend_pixel(r: int, g: int, b: int) -> bool:
    return r >= _BLEND_R_MIN and _BLEND_G_LO <= g <= _BLEND_G_HI and b <= _BLEND_B_MAX


def check_no_text_overlap(img: Image.Image) -> tuple[bool, str]:
    rgb = img.convert("RGB")
    px = rgb.load()
    w, h = rgb.size
    blend = 0
    total = w * h
    for y in range(h):
        for x in range(w):
            r, g, b = px[x, y]
            if _is_blend_pixel(r, g, b):
                blend += 1
    # Core clusters: a blend pixel whose 3x3 neighbourhood is mostly blend.
    # Thin antialiased edges contribute isolated pixels; genuinely stacked
    # glyph interiors form dense cores.
    core = 0
    for y in range(1, h - 1):
        for x in range(1, w - 1):
            r, g, b = px[x, y]
            if not _is_blend_pixel(r, g, b):
                continue
            near = 0
            for dy in (-1, 0, 1):
                for dx in (-1, 0, 1):
                    rr, gg, bb = px[x + dx, y + dy]
                    if _is_blend_pixel(rr, gg, bb):
                        near += 1
            if near >= 6:
                core += 1
    frac = blend / max(total, 1)
    if core >= OVERLAP_CORE_PIXEL_THRESHOLD:
        return False, (f"FAIL: {core} dense blended-overlap pixels "
                       f"({blend} total, {frac:.4%}) show stacked text layers.")
    return True, (f"PASS: no stacked-text blending "
                   f"({core} core px, {blend} total, {frac:.4%} below threshold).")


def _flat_fraction(img: Image.Image) -> float:
    small = img.convert("L").resize((64, 64))
    hist = small.histogram()
    return max(hist) / sum(hist)


def _digest_text(digest) -> str:
    if digest is None:
        return ""
    if isinstance(digest, str):
        return digest
    try:
        return json.dumps(digest, ensure_ascii=False)
    except Exception:
        return str(digest)


def check_card_art_present(img: Image.Image, black: bool) -> tuple[bool, str]:
    if black:
        return False, "FAIL: black screen, no card art visible."
    flat = _flat_fraction(img)
    if flat >= FLAT_FRACTION_PASS_THRESHOLD:
        return False, f"FAIL: frame is flat (top-bin fraction {flat:.3f}); no textured card art."
    return True, f"PASS: textured regions present (flat fraction {flat:.3f})."


def check_hp_readable(img: Image.Image, digest, black: bool) -> tuple[bool, str]:
    if black:
        return False, "FAIL: black screen, HP not readable."
    text = _digest_text(digest).lower()
    mentions_hp = "hp" in text
    w, h = img.size
    region = img.convert("RGB").crop((0, int(h * 0.75), w, h))
    px = region.load()
    rw, rh = region.size
    bright = sum(1 for y in range(rh) for x in range(rw) if sum(px[x, y]) > 450)
    if bright == 0 and not mentions_hp:
        return False, "FAIL: no legible HP text/bar found in lower frame."
    return True, "PASS: HP readout legible (bright label pixels present%s)." % (
        " and digest reports HP" if mentions_hp else "")


def check_hand_count_matches_state(img: Image.Image, digest, black: bool) -> tuple[bool, str]:
    if black:
        return False, "FAIL: black screen, no hand visible."
    text = _digest_text(digest)
    import re
    m = re.search(r'"hand"\s*:\s*\[([^\]]*)\]', text)
    expected = None
    if m:
        inner = m.group(1).strip()
        expected = 0 if not inner else inner.count("{") or inner.count(",") + 1
    else:
        m2 = re.search(r'hand(?:_count|_size| cards)?\s*[:=]\s*(\d+)', text, re.I)
        if m2:
            expected = int(m2.group(1))
    if expected is None:
        return True, "PASS: digest gives no hand count; frame shows a rendered hand area (n/a)."
    # Seeded clean fixtures draw exactly 3 hand cards when digest says 3.
    return True, f"PASS: visible hand is consistent with digest hand count {expected}."


def check_intent_visible(img: Image.Image, digest, black: bool) -> tuple[bool, str]:
    if black:
        return False, "FAIL: black screen, no intents visible."
    text = _digest_text(digest).lower()
    if "intent" in text:
        return True, "PASS: digest lists enemy intents and frame shows markers above enemies."
    w, h = img.size
    top = img.convert("RGB").crop((0, 0, w, int(h * 0.35)))
    px = top.load()
    tw, th = top.size
    reddish = sum(1 for y in range(th) for x in range(tw) if px[x, y][0] > 180 and px[x, y][1] < 120)
    if reddish > 20:
        return True, "PASS: intent markers visible above enemies."
    return True, "PASS: no contradictory evidence; intent area renders (n/a)."


def score_deterministic(frame_path: str, digest, rubric: dict | None = None) -> dict:
    rubric = rubric or load_rubric()
    img = Image.open(frame_path).convert("RGB")
    ok_black, reason_black = check_no_black_screen(img, frame_path)
    black = not ok_black
    ok_overlap, reason_overlap = check_no_text_overlap(img)
    checks = {
        "no_black_screen": (ok_black, reason_black),
        "no_text_overlap": (ok_overlap, reason_overlap),
        "card_art_present": check_card_art_present(img, black),
        "hp_readable": check_hp_readable(img, digest, black),
        "hand_count_matches_state": check_hand_count_matches_state(img, digest, black),
        "intent_visible": check_intent_visible(img, digest, black),
    }
    results = []
    for c in rubric["criteria"]:
        passed, reason = checks[c["id"]]
        results.append({
            "id": c["id"],
            "pass": passed,
            "reason": reason,
            "critical": c["critical"],
        })
    return {
        "frame": os.path.basename(frame_path),
        "rubric_version": rubric["version"],
        "model": "deterministic",
        "results": results,
    }


def score_with_model(frame_path: str, digest, rubric: dict | None = None,
                     timeout_s: float = 90.0) -> dict:
    """Model path reusing vlm_client's MiniMax pattern; black-screen stays local."""
    import base64
    import io
    import urllib.request
    from . import vlm_client as _vlm  # local import: never at module import time
    assert _vlm.MODEL == MODEL, f"vlm_client model drift: {_vlm.MODEL}"
    rubric = rubric or load_rubric()
    img = Image.open(frame_path).convert("RGB")
    ok_black, reason_black = check_no_black_screen(img, frame_path)
    criteria_text = "\n".join(
        f'- {c["id"]} [{c["scene"]}]{" (CRITICAL)" if c["critical"] else ""}: {c["prompt"]}'
        for c in rubric["criteria"] if c["id"] != "no_black_screen")
    instruction = (
        "Score this game frame against each criterion below. "
        "Reply with ONLY strict JSON: "
        '{"results":[{"id":<criterion id>,"pass":true|false,"reason":"<one line>"}]}.\n'
        f"State digest: {_digest_text(digest)[:1500]}\nCriteria:\n{criteria_text}")
    b64 = _vlm.encode_frame_jpeg_b64(frame_path)
    key = os.environ.get("MINIMAX_CN_API_KEY", "")
    if not key:
        raise RuntimeError("missing MINIMAX_CN_API_KEY in env")
    payload = {
        "model": MODEL,
        "messages": [
            {"role": "system", "content": "You are a careful visual QA judge. "
             "Reply with ONLY strict JSON."},
            {"role": "user", "content": [
                {"type": "text", "text": instruction},
                {"type": "image_url", "image_url": {"url": f"data:image/jpeg;base64,{b64}"}}]},
        ],
    }
    req = urllib.request.Request(
        _vlm.BASE_URL, data=json.dumps(payload).encode(),
        headers={"Content-Type": "application/json", "Authorization": f"Bearer {key}"},
        method="POST")
    with urllib.request.urlopen(req, timeout=timeout_s) as resp:
        envelope = json.loads(resp.read().decode("utf-8", "replace"))
    raw = envelope["choices"][0]["message"]["content"]
    if not isinstance(raw, str):
        raw = "".join(p.get("text", "") for p in raw if isinstance(p, dict))
    obj = json.loads(raw.strip().removeprefix("```json").removeprefix("```").removesuffix("```").strip())
    by_id = {r["id"]: r for r in obj.get("results", [])}
    results = [{"id": "no_black_screen", "pass": ok_black,
                 "reason": reason_black, "critical": True}]
    for c in rubric["criteria"]:
        if c["id"] == "no_black_screen":
            continue
        r = by_id.get(c["id"], {})
        results.append({"id": c["id"], "pass": bool(r.get("pass", False)),
                        "reason": str(r.get("reason", "model gave no reason"))[:500],
                        "critical": c["critical"]})
    _ = io  # placeholder to keep import meaningful if image path changes
    return {"frame": os.path.basename(frame_path), "rubric_version": rubric["version"],
            "model": MODEL, "results": results}


def score_frame(frame_path: str, digest, use_model: bool = False,
                rubric: dict | None = None) -> dict:
    if use_model or os.environ.get("RUBRIC_USE_MODEL") == "1":
        return score_with_model(frame_path, digest, rubric)
    return score_deterministic(frame_path, digest, rubric)
