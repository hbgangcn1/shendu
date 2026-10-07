"""Probe minimax-cn/MiniMax-M3 image input with a real game screenshot."""
import base64
import io
import json
import os
import sys
import urllib.request

SRC = "C:/Users/hbgan/Projects/shendu/qa-captures/main_menu.png"
BASE_URL = "https://api.minimaxi.com/v1/chat/completions"
MODEL = sys.argv[1] if len(sys.argv) > 1 else "MiniMax-M3"
EFFORT = sys.argv[2] if len(sys.argv) > 2 else None
PROMPT = "List the exact on-screen buttons. Answer in one line."
MAX_W = 1280


def load_image_b64() -> str:
    from PIL import Image

    img = Image.open(SRC).convert("RGB")
    if img.width > MAX_W:
        img = img.resize((MAX_W, int(img.height * MAX_W / img.width)), Image.LANCZOS)
    buf = io.BytesIO()
    img.save(buf, "JPEG", quality=80)
    return base64.b64encode(buf.getvalue()).decode()


def main() -> int:
    key = os.environ.get("MINIMAX_CN_API_KEY", "")
    if not key:
        print("HTTP status: (no request) missing MINIMAX_CN_API_KEY")
        return 1
    try:
        b64 = load_image_b64()
    except Exception as e:
        print(f"HTTP status: (no request) image load failed: {e}")
        return 1
    payload = {
        "model": MODEL,
        **({"reasoning_effort": EFFORT} if EFFORT else {}),
        "messages": [
            {
                "role": "user",
                "content": [
                    {"type": "text", "text": PROMPT},
                    {"type": "image_url", "image_url": {"url": f"data:image/jpeg;base64,{b64}"}},
                ],
            }
        ],
    }
    last_status: object = "(no response)"
    body = ""
    for attempt in range(3):
        req = urllib.request.Request(
            BASE_URL,
            data=json.dumps(payload).encode(),
            headers={"Content-Type": "application/json", "Authorization": f"Bearer {key}"},
            method="POST",
        )
        try:
            with urllib.request.urlopen(req, timeout=90) as resp:
                last_status = resp.status
                body = resp.read().decode("utf-8", "replace")
            break
        except Exception as e:
            last_status = getattr(e, "code", "(no response)")
            try:
                body = e.read().decode("utf-8", "replace")  # type: ignore
            except Exception:
                body = f"{type(e).__name__}: {e} (attempt {attempt + 1}/3)"
    status = last_status
    print(f"HTTP status: {status}")
    print(f"Raw reply: {body}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
