#!/usr/bin/env python3
import subprocess
import sys

# Use Godot to dump autoloads and project settings
godot = r"C:\Tools\Godot\Godot_v4.7-stable_win64.exe"
project = r"C:\Users\hbgan\Projects\shendu"

cmd = [
    godot,
    "--headless",
    "--path", project,
    "--script", "res://scripts/qa/debug_gamestate2.gd",
    "--quit"
]

result = subprocess.run(cmd, capture_output=True, text=True, timeout=60)
print("STDOUT:")
print(result.stdout)
print("STDERR:")
print(result.stderr)
print("Return code:", result.returncode)