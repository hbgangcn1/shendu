"""MiniMax MiniMax-M3 vision caller for the shendu sight-play loop.

Pattern extends tools/vision/probe_vision.py (HTTP 200 proven):
urllib POST to the minimax-cn chat-completions endpoint, user message =
[text digest, image_url base64 JPEG q80 max 1280 wide].

Credentials come from env only (MINIMAX_CN_API_KEY). Nothing is hardcoded.
"""
import base64
import io
import json
import os
import time
import urllib.request

BASE_URL = "https://api.minimaxi.com/v1/chat/completions"
MODEL = "MiniMax-M3.1-Flash-Preview"
FALLBACK_MODEL = "MiniMax-M3"
MAX_W = 1280

ALLOWED_ACTIONS = (
    "play_card",
    "end_turn",
    "select_node",
    "confirm_node",
    "pick_reward",
    "skip_reward",
    "take_card",
    "confirm_select",
    "select_chenmo",
    "select_suwan",
    "wait",
)

ACTION_GRAMMAR = """You play the game by choosing ONE action as strict JSON.
Allowed actions (action + args):
- {"action":"play_card","args":{"index":<hand index 0-based>}}
- {"action":"end_turn","args":{}}
- {"action":"select_node","args":{"node_id":"<map node id>"}}
- {"action":"confirm_node","args":{}}
- {"action":"pick_reward","args":{"index":<0-2>}}
- {"action":"skip_reward","args":{}}
- {"action":"take_card","args":{"index":<0-2>}}
- {"action":"confirm_select","args":{}}
- {"action":"select_chenmo","args":{}}
- {"action":"select_suwan","args":{}}
- {"action":"wait","args":{}} (do nothing this tick)
Reply with ONLY one JSON object: {"action":<one of the above>,"args":{...},"rationale":"<one line>","confidence":<0.0-1.0>}.
Rules: pick select_node only for a node listed reachable in the digest; pick play_card only for a playable hand card; in character_select use select_chenmo/select_suwan then confirm_select; in reward use pick_reward/take_card or skip_reward; if unsure, wait."""

PERSONA = (
    "You are a careful playtester playing the Chinese roguelike card game "
    "Shendu by sight. Read the screenshot first, use the text digest only "
    "as backup. Prefer safe progress over fast progress."
)


def system_prompt() -> str:
    return ACTION_GRAMMAR + "\n" + PERSONA


def encode_frame_jpeg_b64(png_path: str) -> str:
    from PIL import Image

    img = Image.open(png_path).convert("RGB")
    if img.width > MAX_W:
        img = img.resize((MAX_W, int(img.height * MAX_W / img.width)), Image.LANCZOS)
    buf = io.BytesIO()
    img.save(buf, "JPEG", quality=80)
    return base64.b64encode(buf.getvalue()).decode()


class MalformedReply(ValueError):
    """Model output failed strict parse; carries the full raw reply."""

    def __init__(self, message: str, raw: str):
        super().__init__(message)
        self.raw = raw


def call_m3(digest_text: str, frame_png_path: str, timeout_s: float = 90.0) -> tuple[dict, int, str]:
    """Call MiniMax-M3. Returns (parsed_json, latency_ms, raw_reply).

    Raises RuntimeError on transport failure (caller decides abort/retry).
    Raises ValueError on malformed model output (caller re-asks once).
    """
    key = os.environ.get("MINIMAX_CN_API_KEY", "")
    if not key:
        raise RuntimeError("missing MINIMAX_CN_API_KEY in env")
    b64 = encode_frame_jpeg_b64(frame_png_path)
    payload = {
        "model": MODEL,
        "messages": [
            {"role": "system", "content": system_prompt()},
            {
                "role": "user",
                "content": [
                    {"type": "text", "text": digest_text},
                    {"type": "image_url", "image_url": {"url": f"data:image/jpeg;base64,{b64}"}},
                ],
            },
        ],
    }
    t0 = time.time()
    req = urllib.request.Request(
        BASE_URL,
        data=json.dumps(payload).encode(),
        headers={"Content-Type": "application/json", "Authorization": f"Bearer {key}"},
        method="POST",
    )
    try:
        with urllib.request.urlopen(req, timeout=timeout_s) as resp:
            body = resp.read().decode("utf-8", "replace")
    except Exception as e:
        raise RuntimeError(f"minimax transport failed: {type(e).__name__}: {e}")
    latency_ms = int((time.time() - t0) * 1000)
    try:
        envelope = json.loads(body)
        raw = envelope["choices"][0]["message"]["content"]
    except Exception as e:
        raise ValueError(f"malformed envelope: {e}; body={body[:300]}")
    if not isinstance(raw, str):
        # Some SDKs return content blocks; join text parts.
        try:
            raw = "".join(p.get("text", "") for p in raw if isinstance(p, dict))
        except Exception:
            raise ValueError(f"non-string content: {raw!r}"[:300])
    try:
        return _parse_strict(raw, MODEL), latency_ms, raw
    except ValueError as e:
        raise MalformedReply(str(e), raw)


def _parse_strict(raw: str, model: str) -> dict:
    text = raw.strip()
    # Tolerate a single fenced code block; nothing else.
    if text.startswith("```"):
        text = text.strip("`").strip()
        if text.lower().startswith("json"):
            text = text[4:].strip()
    try:
        obj = json.loads(text)
    except Exception:
        # Tolerate trailing prose by scanning for the first {...} block.
        start = text.find("{")
        end = text.rfind("}")
        if start < 0 or end <= start:
            raise ValueError(f"non-JSON reply: {raw[:300]}")
        obj = json.loads(text[start:end + 1])
    if not isinstance(obj, dict):
        raise ValueError(f"top-level not object: {raw[:300]}")
    action = obj.get("action")
    if action not in ALLOWED_ACTIONS:
        raise ValueError(f"action {action!r} not in {ALLOWED_ACTIONS}; raw={raw[:300]}")
    args = obj.get("args", {})
    if not isinstance(args, dict):
        raise ValueError(f"args not object: {raw[:300]}")
    rationale = obj.get("rationale", "")
    confidence = obj.get("confidence", 0.0)
    try:
        confidence = float(confidence)
    except Exception:
        raise ValueError(f"confidence not numeric: {raw[:300]}")
    return {
        "action": action,
        "args": args,
        "rationale": str(rationale)[:500],
        "confidence": confidence,
        "vlm_model": model,
    }


def reask_once(digest_text: str, frame_png_path: str, raw_reply: str,
               timeout_s: float = 90.0) -> tuple[dict, int, str]:
    """Second and final attempt: show the model its raw reply and demand fix."""
    key = os.environ.get("MINIMAX_CN_API_KEY", "")
    if not key:
        raise RuntimeError("missing MINIMAX_CN_API_KEY in env")
    b64 = encode_frame_jpeg_b64(frame_png_path)
    repair = (
        "Your previous reply was not valid strict JSON:\n"
        f"{raw_reply[:2000]}\n"
        "Reply again with ONLY one JSON object "
        '{"action":<allowed>,"args":{...},"rationale":"...","confidence":0.0-1.0}.'
    )
    payload = {
        "model": MODEL,
        "messages": [
            {"role": "system", "content": system_prompt()},
            {
                "role": "user",
                "content": [
                    {"type": "text", "text": digest_text + "\n" + repair},
                    {"type": "image_url", "image_url": {"url": f"data:image/jpeg;base64,{b64}"}},
                ],
            },
        ],
    }
    t0 = time.time()
    req = urllib.request.Request(
        BASE_URL,
        data=json.dumps(payload).encode(),
        headers={"Content-Type": "application/json", "Authorization": f"Bearer {key}"},
        method="POST",
    )
    try:
        with urllib.request.urlopen(req, timeout=timeout_s) as resp:
            body = resp.read().decode("utf-8", "replace")
    except Exception as e:
        raise RuntimeError(f"minimax re-ask transport failed: {type(e).__name__}: {e}")
    latency_ms = int((time.time() - t0) * 1000)
    try:
        envelope = json.loads(body)
        raw2 = envelope["choices"][0]["message"]["content"]
    except Exception as e:
        raise ValueError(f"malformed envelope on re-ask: {e}")
    if not isinstance(raw2, str):
        raw2 = "".join(p.get("text", "") for p in raw2 if isinstance(p, dict))
    return _parse_strict(raw2, MODEL), latency_ms, raw2
