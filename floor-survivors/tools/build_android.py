"""Build the Android APK (and optionally send it to your phone over Telegram).

    python tools/build_android.py            # build build/floor-survivors.apk
    python tools/build_android.py --send     # ...and send it via the Telegram bot
    python tools/build_android.py --host none   # no PC Ollama: the phone always uses local fallbacks

Uses the Android toolchain set up under C:\\Android for game-idea-pipeline (SDK, JDK 17, debug keystore,
Godot export templates) - see that project's README if this PC is ever rebuilt.

The phone has no Ollama, so the APK bakes in this PC's LAN address (res://ollama_host.txt): on the same
Wi-Fi, the System AI, achievements and loot run on this PC's model. For that, Ollama must listen on the
LAN and the firewall must allow it (one-time, see docs/android.md).
"""

import argparse
import os
import socket
import subprocess
import sys
from pathlib import Path

GAME = Path(__file__).resolve().parent.parent
GODOT = Path(os.environ.get("GODOT", r"C:\Users\diego\AppData\Local\Microsoft\WinGet\Packages"
             r"\GodotEngine.GodotEngine_Microsoft.Winget.Source_8wekyb3d8bbwe\Godot_v4.7.2-stable_win64_console.exe"))
ANDROID_SDK = r"C:\Android\sdk"
JAVA_HOME = r"C:\Program Files\Microsoft\jdk-17.0.20.101-hotspot"
APK = GAME / "build" / "floor-survivors.apk"
HOST_FILE = GAME / "ollama_host.txt"


def lan_ip() -> str:
    """The IPv4 this PC uses on the local network (no packet is actually sent)."""
    with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as s:
        s.connect(("192.168.1.1", 80))
        return s.getsockname()[0]


def run(args, **kw):
    env = {**os.environ, "ANDROID_HOME": ANDROID_SDK, "ANDROID_SDK_ROOT": ANDROID_SDK, "JAVA_HOME": JAVA_HOME}
    proc = subprocess.run([str(GODOT), "--headless", "--path", str(GAME), *args],
                          capture_output=True, text=True, env=env, timeout=600, **kw)
    return proc


def send_telegram(path: Path, caption: str):
    import requests
    token, chat = os.environ.get("TELEGRAM_BOT_TOKEN"), os.environ.get("TELEGRAM_CHAT_ID")
    if not token or not chat:
        sys.exit("TELEGRAM_BOT_TOKEN / TELEGRAM_CHAT_ID not set; the APK is at " + str(path))
    with open(path, "rb") as f:
        r = requests.post(f"https://api.telegram.org/bot{token}/sendDocument",
                          data={"chat_id": chat, "caption": caption}, files={"document": (path.name, f)}, timeout=300)
    if not r.json().get("ok"):
        sys.exit(f"Telegram send failed: {r.text[:300]}")
    print("sent to Telegram")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--host", help="Ollama host baked into the APK (default: this PC's LAN IP; 'none' to skip)")
    ap.add_argument("--send", action="store_true", help="send the APK to your phone via the Telegram bot")
    args = ap.parse_args()

    host = args.host or lan_ip()
    if host == "none":
        HOST_FILE.unlink(missing_ok=True)
        print("no Ollama host baked in: the phone will always use local fallbacks")
    else:
        HOST_FILE.write_text(host + "\n", encoding="utf-8")
        print(f"Ollama host baked in: {host}:11434")

    APK.parent.mkdir(exist_ok=True)
    print("importing...")
    run(["--import"])
    print("exporting APK (a minute or two)...")
    proc = run(["--export-debug", "Android", str(APK)])
    if proc.returncode != 0 or not APK.exists():
        print(proc.stdout[-3000:], proc.stderr[-3000:], sep="\n")
        sys.exit("export failed")
    print(f"built {APK} ({APK.stat().st_size / 1e6:.1f} MB)")
    if args.send:
        send_telegram(APK, "Floor Survivors - tap to download, then install. "
                           "Left thumb: move. Right thumb: drag = laser, tap = bomb.")


if __name__ == "__main__":
    main()
