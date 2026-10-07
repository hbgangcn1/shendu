"""Seeded fixture test for the offline visual-rubric scorer. Runs under plain python.

Fixture provenance (documented per task):
- fixtures/black_frame.png: generated programmatically (640x360 solid black).
- fixtures/overlap_frame.png: drawn fully with PIL (no qa-captures pixels):
  a mock battle scene (slate background, HP label, 3 textured hand cards,
  enemy intent marker) plus TWO OVERLAPPING text layers in the card area:
  yellow 'FIREBALL DEAL 8' with red 'GUARD BLOCK 5' drawn ~12px offset
  using the same bitmap font, so glyph strokes stack and blend to orange.
  Good counterparts are drawn by the same code with the labels separated.

Checks: schema validity; black fixture FAILs no_black_screen; overlap
fixture FAILs no_text_overlap; each good counterpart PASSes its criterion;
a .black marker sibling forces FAIL deterministically. Exit 0 on success.
"""
import json
import os
import sys
import tempfile

from PIL import Image, ImageDraw, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
FIX = os.path.join(HERE, "fixtures")
BLACK_FIXTURE = os.path.join(FIX, "black_frame.png")
OVERLAP_FIXTURE = os.path.join(FIX, "overlap_frame.png")

sys.path.insert(0, os.path.dirname(HERE))  # tools/ on path for vision package
from vision.rubric_scorer import load_rubric, score_frame  # noqa: E402

W, H = 640, 360
BG = (18, 24, 38)
EXPECTED_IDS = ["no_black_screen", "no_text_overlap", "card_art_present",
                "hp_readable", "hand_count_matches_state", "intent_visible"]

DIGEST = {"scene": "battle", "hp": [72, 80],
          "hand": [{"name": "a"}, {"name": "b"}, {"name": "c"}],
          "intents": ["attack 8"]}


def draw_base(draw: ImageDraw.ImageDraw, font) -> None:
    draw.rectangle([0, 0, W, H], fill=BG)
    draw.text((16, 12), "HP 72/80", fill=(255, 255, 255), font=font)
    draw.rectangle([16, 34, 150, 44], outline=(90, 200, 120), width=2)
    draw.rectangle([18, 36, 18 + int(132 * 72 / 80), 42], fill=(60, 180, 90))
    # Enemy + red intent marker.
    draw.ellipse([460, 40, 560, 140], fill=(120, 70, 80))
    draw.text((468, 16), "ATK 8", fill=(255, 90, 80), font=font)
    # 3 hand cards with textured (non-flat) art boxes.
    for i in range(3):
        x0 = 60 + i * 180
        draw.rectangle([x0, 190, x0 + 150, 330], outline=(200, 190, 150), width=2)
        for yy in range(200, 260):
            for xx in range(x0 + 10, x0 + 140, 4):
                draw.point((xx, yy), fill=((xx * 7 + yy * 13) % 256, 60, 90))
        draw.text((x0 + 12, 270), f"CARD {i}", fill=(240, 240, 240), font=font)


def draw_scene(path: str, overlap: bool) -> None:
    img = Image.new("RGB", (W, H), BG)
    draw = ImageDraw.Draw(img)
    draw_base(draw, ImageFont.load_default())
    big = ImageFont.load_default(size=28)
    if overlap:
        # Two genuinely overlapping layers: opaque yellow label, then a
        # semi-transparent red label ~10px offset so glyph strokes stack and
        # alpha-blend to orange across the stroke interiors.
        draw.text((90, 100), "FIREBALL DEAL 8", fill=(255, 255, 0), font=big)
        layer = Image.new("RGBA", (W, H), (0, 0, 0, 0))
        ImageDraw.Draw(layer).text((100, 106), "GUARD BLOCK 5",
                                   fill=(255, 0, 0, 160), font=big)
        img = Image.alpha_composite(img.convert("RGBA"), layer).convert("RGB")
    else:
        draw.text((90, 100), "FIREBALL DEAL 8", fill=(255, 255, 255), font=big)
        draw.text((90, 160), "GUARD BLOCK 5", fill=(150, 255, 150), font=big)
    img.save(path)


def verdict(report: dict, cid: str) -> tuple:
    for r in report["results"]:
        if r["id"] == cid:
            return r["pass"], r["reason"]
    raise AssertionError(f"missing criterion {cid}")


def check(cond: bool, msg: str) -> None:
    print(("PASS " if cond else "FAIL ") + msg)
    if not cond:
        raise AssertionError(msg)


def main() -> None:
    rubric = load_rubric()
    check(rubric["version"] == "1.0.0", "rubric version 1.0.0")
    check([c["id"] for c in rubric["criteria"]] == EXPECTED_IDS, "rubric covers all 6 criteria")
    check(all(isinstance(c["critical"], bool) for c in rubric["criteria"]), "critical flags are bool")

    for name in ("black_frame.png", "overlap_frame.png"):
        check(os.path.exists(os.path.join(FIX, name)), f"seeded fixture present: {name}")

    black = score_frame(BLACK_FIXTURE, DIGEST)
    overlap = score_frame(OVERLAP_FIXTURE, DIGEST)
    print(json.dumps(black, indent=1))
    print(json.dumps(overlap, indent=1))
    check(isinstance(black["results"], list) and len(black["results"]) == 6, "black report has 6 results")
    check(all(set(r) >= {"id", "pass", "reason"} and isinstance(r["pass"], bool)
                        for r in black["results"] + overlap["results"]), "strict per-criterion schema")

    bp, _ = verdict(black, "no_black_screen")
    check(bp is False, "black fixture FAILs no_black_screen")
    op, _ = verdict(overlap, "no_text_overlap")
    check(op is False, "overlap fixture FAILs no_text_overlap")

    with tempfile.TemporaryDirectory() as tmp:
        good_black = os.path.join(tmp, "good_clean.png")
        good_overlap = os.path.join(tmp, "good_separate.png")
        draw_scene(good_black, overlap=False)
        draw_scene(good_overlap, overlap=False)
        gb = score_frame(good_black, DIGEST)
        go = score_frame(good_overlap, DIGEST)
        print(json.dumps(gb, indent=1))
        print(json.dumps(go, indent=1))
        gbp, _ = verdict(gb, "no_black_screen")
        check(gbp is True, "good counterpart PASSes no_black_screen")
        gop, _ = verdict(go, "no_text_overlap")
        check(gop is True, "good counterpart PASSes no_text_overlap")

        # .black marker sibling forces FAIL without the model, even on a good frame.
        marker = good_black + ".black"
        with open(marker, "w", encoding="utf-8") as f:
            f.write("seeded black-screen flag")
        try:
            mb = score_frame(good_black, DIGEST)
            mbp, mbr = verdict(mb, "no_black_screen")
            check(mbp is False and "marker" in mbr, ".black marker forces no_black_screen FAIL")
            check(mb["model"] == "deterministic", "marker path never calls the model")
        finally:
            os.remove(marker)

    print("ALL RUBRIC TESTS PASSED")


if __name__ == "__main__":
    main()
