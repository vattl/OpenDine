# -*- coding: utf-8 -*-
"""Add GET /kds/device/me to openapi.yaml."""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PATH = ROOT / "docs" / "openapi.yaml"
text = PATH.read_text(encoding="utf-8")

if "/kds/device/me:" in text:
    print("already present")
    raise SystemExit(0)

CHANGELOG = """    - **v1.2.90（KDS·设备当前绑定查询）**：新增 **`GET /kds/device/me`**，携带 **`X-Kds-Device-Token`** 返回当前令牌绑定的 **`device`**（`shop_id`、`screen_tag`、`device_code` 等），供 App 启动/刷新前核对屏型，**不**触发重新 login。
"""
text = text.replace("  version: 1.2.89\n", CHANGELOG + "  version: 1.2.90\n")

PATH_BLOCK = """
  /kds/device/me:
    get:
      tags: [KDS-Client]
      summary: 查询当前令牌绑定的设备
      description: |
        携带 **`X-Kds-Device-Token`**，返回该令牌在服务端登记的设备行（**`device`**）。
        用于 App 冷启动、页面刷新前核对 **`screen_tag` / `shop_id`**，避免本地缓存屏型与 token 不一致。
        **不会**刷新 token；换屏须 **`POST /kds/device/login`**。
        令牌无效或设备已禁用时返回 **401**。
      parameters:
        - $ref: '#/components/parameters/XKdsDeviceToken'
      responses:
        '200':
          description: '`code=0`，`device` 为 **KdsDevice**（含 `device_token`、`screen_tag`）'
          content:
            application/json:
              schema:
                type: object
                properties:
                  code: { type: integer, example: 0 }
                  device: { $ref: '#/components/schemas/KdsDevice' }
        '401':
          description: 缺少或无效设备令牌

"""

text = text.replace("\n  /kds/device/heartbeat:\n", PATH_BLOCK + "\n  /kds/device/heartbeat:\n", 1)

text = text.replace(
    "      1. POST /kds/device/login  → 保存 device_token、确认 screen_tag\n",
    "      1. POST /kds/device/login  → 保存 device_token、确认 screen_tag\n"
    "      1b. GET /kds/device/me（已有 token 时）→ 核对绑定屏，勿用下拉改屏代替 login\n",
)

text = text.replace(
    "      | 白名单 | **`POST /kds/device/login`** 无需 token |\n",
    "      | 白名单 | **`POST /kds/device/login`**、**`POST /kds/device/heartbeat`** 无需 token；**`GET /kds/device/me`** 必须带 token |\n",
)

text = text.replace(
    "        除 **`POST /kds/device/login`** 外，所有 **`/kds/*`** 请求必须携带",
    "        除 **`POST /kds/device/login`**、**`POST /kds/device/heartbeat`** 外，所有 **`/kds/*`** 请求必须携带",
)

PATH.write_text(text, encoding="utf-8", newline="\n")
print("patched", PATH)
