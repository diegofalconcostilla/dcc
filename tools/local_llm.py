"""Offload bulk text/vision work to the local Ollama models instead of a paid/limited cloud model.

Claude Code (or you) plans and reviews; this does the token-heavy middle:

  # text: prompt + optional context files -> stdout or --out (add --json to force valid JSON)
  python tools/local_llm.py text --prompt "Summarize" --context plan.md --out summary.md
  python tools/local_llm.py text --prompt-file ask.txt --json --out result.json

  # vision: describe images with llava, one JSON line per image (resumable: skips done ones)
  python tools/local_llm.py vision --prompt "Describe this sprite" --out catalog.jsonl img1.png img2.png

Models default to what's installed here (qwen2.5:7b for text, llava for vision); override with --model.
"""

import argparse
import base64
import json
import re
import sys
from pathlib import Path

import requests

OLLAMA = "http://localhost:11434"
TEXT_MODEL = "qwen2.5:7b"
VISION_MODEL = "llava:latest"


def generate(prompt, model, *, json_mode=False, images=None, temperature=0.4, num_ctx=16384, timeout=600):
    body = {
        "model": model,
        "prompt": prompt,
        "stream": False,
        "options": {"temperature": temperature, "num_ctx": num_ctx},
    }
    if json_mode:
        body["format"] = "json"
    if images:
        body["images"] = images
    r = requests.post(f"{OLLAMA}/api/generate", json=body, timeout=timeout)
    r.raise_for_status()
    return r.json()["response"].strip()


def parse_json(text):
    text = re.sub(r"```(?:json)?", "", text)
    start = min(i for i in (text.find("{"), text.find("[")) if i != -1)
    obj, _ = json.JSONDecoder().raw_decode(text[start:])
    return obj


def cmd_text(args):
    prompt = args.prompt or Path(args.prompt_file).read_text(encoding="utf-8")
    for ctx in args.context or []:
        prompt += f"\n\n--- {ctx} ---\n" + Path(ctx).read_text(encoding="utf-8")
    for attempt in range(3):
        out = generate(prompt, args.model or TEXT_MODEL, json_mode=args.json, temperature=args.temperature)
        if not args.json:
            break
        try:
            out = json.dumps(parse_json(out), indent=2, ensure_ascii=False)
            break
        except (ValueError, json.JSONDecodeError):
            print(f"invalid JSON on attempt {attempt + 1}, retrying", file=sys.stderr)
    else:
        sys.exit("local model never produced valid JSON")
    if args.out:
        Path(args.out).write_text(out + "\n", encoding="utf-8")
        print(f"wrote {args.out} ({len(out)} chars)")
    else:
        print(out)


def cmd_vision(args):
    out = Path(args.out)
    done = set()
    if out.exists():
        done = {json.loads(line)["image"] for line in out.read_text(encoding="utf-8").splitlines() if line.strip()}
    with out.open("a", encoding="utf-8") as f:
        for i, img in enumerate(args.images, 1):
            if img in done:
                continue
            b64 = base64.b64encode(Path(img).read_bytes()).decode()
            desc = generate(args.prompt, args.model or VISION_MODEL, images=[b64], temperature=0.2, num_ctx=4096)
            f.write(json.dumps({"image": img, "description": desc}, ensure_ascii=False) + "\n")
            f.flush()
            print(f"[{i}/{len(args.images)}] {Path(img).name}: {desc[:70]}")


def main():
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = p.add_subparsers(dest="cmd", required=True)

    t = sub.add_parser("text")
    g = t.add_mutually_exclusive_group(required=True)
    g.add_argument("--prompt")
    g.add_argument("--prompt-file")
    t.add_argument("--context", nargs="*")
    t.add_argument("--json", action="store_true")
    t.add_argument("--model")
    t.add_argument("--temperature", type=float, default=0.4)
    t.add_argument("--out")

    v = sub.add_parser("vision")
    v.add_argument("--prompt", required=True)
    v.add_argument("--model")
    v.add_argument("--out", required=True)
    v.add_argument("images", nargs="+")

    args = p.parse_args()
    {"text": cmd_text, "vision": cmd_vision}[args.cmd](args)


if __name__ == "__main__":
    main()
