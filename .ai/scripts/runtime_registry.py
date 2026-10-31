#!/usr/bin/env python3
"""Minimal crash-safe shared runtime registry helper.

Project-local and intentionally dependency-free. It records lightweight workstream
metadata; it never modifies Git or source files.
"""
from pathlib import Path
import argparse, json, datetime, sys

def now():
    return datetime.datetime.now().astimezone().isoformat(timespec="seconds")

def load(path):
    if not path.exists(): return {"workstreams": {}}
    try: return json.loads(path.read_text(encoding="utf-8"))
    except Exception: return {"workstreams": {}}

def save(path, data):
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_suffix(".tmp")
    tmp.write_text(json.dumps(data, ensure_ascii=False, indent=2), encoding="utf-8")
    tmp.replace(path)

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("action", choices=["register", "heartbeat", "status", "complete", "interrupt"])
    ap.add_argument("--id")
    ap.add_argument("--parent")
    ap.add_argument("--title")
    ap.add_argument("--worktree")
    ap.add_argument("--branch")
    ap.add_argument("--phase")
    ap.add_argument("--task")
    ap.add_argument("--step")
    ap.add_argument("--dirty", choices=["true","false"])
    ap.add_argument("--root", default=".")
    args = ap.parse_args()
    path = Path(args.root).resolve()/".ai-runtime"/"registry.json"
    data = load(path)
    ws = data.setdefault("workstreams", {})
    if args.action == "status":
        print(json.dumps(data, ensure_ascii=False, indent=2)); return 0
    if not args.id:
        print("--id required", file=sys.stderr); return 2
    item = ws.setdefault(args.id, {"id": args.id, "created_at": now()})
    if args.action == "register": item["status"] = "REGISTERED"
    elif args.action == "heartbeat": item["status"] = item.get("status") if item.get("status") not in {"REGISTERED","INTERRUPTED"} else "ACTIVE"
    elif args.action == "complete": item["status"] = "COMPLETED"
    elif args.action == "interrupt": item["status"] = "INTERRUPTED"
    for k in ("parent","title","worktree","branch","phase","task","step"):
        v=getattr(args,k)
        if v is not None: item[k]=v
    if args.dirty is not None: item["dirty"] = args.dirty == "true"
    item["last_activity"] = now()
    save(path, data)
    print(json.dumps(item, ensure_ascii=False, indent=2))
    return 0

if __name__ == "__main__":
    sys.exit(main())
