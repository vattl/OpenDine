# -*- coding: utf-8 -*-
"""Remove duplicate KDS blocks accidentally merged into openapi.yaml."""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PATH = ROOT / "docs" / "openapi.yaml"
text = PATH.read_text(encoding="utf-8")

# 1) Duplicate paths inserted before components (from patch_openapi_kds_expedition.py)
marker_paths = "\n\n  # ---------- KDS 厨显（设备 token）----------\n  /kds/overview/board:"
idx = text.find(marker_paths)
if idx != -1:
    # only remove if /kds/expedition/board appears twice
    if text.count("  /kds/expedition/board:") > 1:
        end = text.find("\ncomponents:\n", idx)
        if end != -1:
            text = text[:idx] + text[end:]
            print("removed duplicate paths block before components")

# 2) First duplicate schemas after zsqDispatchStatus (patch script)
start_schema = text.find(
    "\n\n    KdsOverviewBoardResponse:\n"
    "      type: object\n"
    "      description: GET /kds/overview/board 与 GET /kds/expedition/board\n"
)
end_schema = text.find("\n\n    KdsItemStatus:\n", start_schema)
if start_schema != -1 and end_schema != -1 and start_schema < end_schema:
    text = text[:start_schema] + text[end_schema:]
    print("removed first duplicate KdsOverview* schema block")

# 3) Third duplicate before KdsGrillBoardResponse
start3 = text.find(
    "\n\n    KdsOverviewBoardResponse:\n"
    "      type: object\n"
    "      description: GET /kds/overview/board 业务字段（与 code 同级平铺于 R）\n"
)
end3 = text.find("\n\n    KdsGrillBoardResponse:\n", start3)
if start3 != -1 and end3 != -1:
    text = text[:start3] + text[end3:]
    print("removed third duplicate KdsOverview* before KdsGrillBoardResponse")

PATH.write_text(text, encoding="utf-8", newline="\n")
print("version line:", [l for l in text.splitlines() if l.strip().startswith("version:")][-1])
print("/kds/expedition/board count:", text.count("  /kds/expedition/board:"))
print("KdsOverviewBoardResponse count:", text.count("    KdsOverviewBoardResponse:"))
print("lines:", text.count("\n") + 1)
