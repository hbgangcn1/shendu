"""Persona library loader/validator for the vision tick loop.

Library schema: {version, personas:[{id, name, system_prompt,
decision_priorities[], risk_appetite, goal_bias, verbosity}]}.
"""
import json
import os

LIBRARY_PATH = os.path.join(os.path.dirname(os.path.abspath(__file__)),
                             "persona_library.json")


def load_library(path: str = LIBRARY_PATH) -> dict:
    with open(path, "r", encoding="utf-8") as f:
        lib = json.load(f)
    validate_library(lib)
    return lib


def validate_library(lib: dict) -> dict:
    if not isinstance(lib, dict):
        raise ValueError("library must be a JSON object")
    if "version" not in lib or "personas" not in lib:
        raise ValueError("library needs 'version' and 'personas'")
    personas = lib["personas"]
    if not isinstance(personas, list) or not personas:
        raise ValueError("'personas' must be a non-empty list")
    seen = set()
    for p in personas:
        for key in ("id", "name", "system_prompt", "decision_priorities",
                    "risk_appetite", "goal_bias", "verbosity"):
            if key not in p:
                raise ValueError(f"persona {p.get('id', '?')} missing '{key}'")
        if not str(p["system_prompt"]).strip():
            raise ValueError(f"persona '{p['id']}' has empty system_prompt")
        if not p["decision_priorities"]:
            raise ValueError(f"persona '{p['id']}' has empty decision_priorities")
        if p["id"] in seen:
            raise ValueError(f"duplicate persona id '{p['id']}'")
        seen.add(p["id"])
    return lib


def get_persona(lib: dict, persona_id: str) -> dict:
    for p in lib["personas"]:
        if p["id"] == persona_id:
            return p
    valid = [p["id"] for p in lib["personas"]]
    raise KeyError(f"unknown persona '{persona_id}'; valid: {valid}")


def render_system_prompt(persona: dict) -> str:
    """Render a persona dict into a system-prompt string fragment."""
    prios = ", ".join(persona["decision_priorities"])
    return (f"{persona['system_prompt'].strip()}\n"
            f"Persona: {persona['name']} (risk appetite: {persona['risk_appetite']}; "
            f"goal: {persona['goal_bias']}; priorities: {prios}).")


def main() -> int:
    lib = load_library()
    print(f"persona library v{lib['version']}: {len(lib['personas'])} personas OK")
    for p in lib["personas"]:
        rendered = render_system_prompt(p)
        print(f"- {p['id']}: system_prompt={len(p['system_prompt'])}ch "
              f"priorities={p['decision_priorities']} "
              f"risk={p['risk_appetite']} rendered={len(rendered)}ch")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
