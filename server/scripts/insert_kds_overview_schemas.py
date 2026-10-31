# -*- coding: utf-8 -*-
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PATH = ROOT / "docs" / "openapi.yaml"
text = PATH.read_text(encoding="utf-8")

if "    KdsOverviewBoardResponse:" in text:
    print("schemas already present")
    raise SystemExit(0)

BLOCK = """
    KdsOverviewBoardResponse:
      type: object
      description: GET /kds/overview/board 与 GET /kds/expedition/board 业务字段（与 code 同级平铺于 R）
      properties:
        screen_tag: { type: string, enum: [boss_overview, expedition] }
        queue: { type: string, enum: [pending, cooking, ready_serve, done] }
        dining: { type: string, enum: [all, dine_in, takeout, pack] }
        view: { type: string, enum: [dish, order, table] }
        extra:
          type: array
          items: { type: string }
        summary:
          type: object
          properties:
            ticket_count: { type: integer }
            order_count: { type: integer }
            dish_quantity: { type: integer }
            rush_count: { type: integer }
            overdue_count: { type: integer }
        dish_groups:
          type: array
          items: { $ref: '#/components/schemas/KdsOverviewDishGroup' }
        order_cards:
          type: array
          items: { $ref: '#/components/schemas/KdsOverviewOrderCard' }

    KdsOverviewDishGroup:
      type: object
      properties:
        dish_name: { type: string }
        screen_tag: { $ref: '#/components/schemas/KdsScreenTag' }
        quantity: { type: integer, description: '待传菜队列下为 remaining_quantity 合计' }
        pending_quantity: { type: integer, description: 合并组内待制作(0)份数 }
        cooking_quantity: { type: integer, description: 合并组内制作中(1)份数 }
        served_quantity: { type: integer, description: 已传菜确认数量合计（ready_serve） }
        remaining_quantity: { type: integer, description: 待传剩余量合计（ready_serve） }
        serve_clickable: { type: integer, enum: [0, 1], description: '出餐屏待传菜是否可点卡传菜' }
        unit: { type: string, nullable: true }
        rush_flag: { type: integer, enum: [0, 1] }
        overdue_flag: { type: boolean }
        ticket_count: { type: integer }
        lines:
          type: array
          items: { $ref: '#/components/schemas/KdsOverviewLine' }

    KdsOverviewOrderCard:
      type: object
      properties:
        order_id: { type: integer }
        order_no: { type: string }
        table_number: { type: string, nullable: true }
        dineInOrTakeOut: { type: string }
        orderNumber: { type: integer, nullable: true }
        remark: { type: string, nullable: true }
        order_time: { type: string, nullable: true }
        rush_flag: { type: integer, enum: [0, 1] }
        items:
          type: array
          items: { $ref: '#/components/schemas/KdsOverviewLine' }

    KdsOverviewLine:
      type: object
      properties:
        ticket_id: { type: integer, format: int64 }
        detail_id: { type: integer }
        order_id: { type: integer }
        order_no: { type: string }
        table_number: { type: string, nullable: true }
        dineInOrTakeOut: { type: string, nullable: true }
        screen_tag: { $ref: '#/components/schemas/KdsScreenTag' }
        item_status: { $ref: '#/components/schemas/KdsItemStatus' }
        item_status_label: { type: string, description: '待制作/制作中/已完成/已退菜' }
        archived: { type: integer }
        skewer_picked: { type: integer, description: '0 未抓串 1 已抓串' }
        name: { type: string }
        quantity: { type: integer, description: '当前队列展示量；ready_serve 为 remaining' }
        line_quantity: { type: integer, description: 明细行总份数 }
        served_quantity: { type: integer, description: 已传菜确认数量 }
        remaining_quantity: { type: integer, description: 待传剩余量 }
        done_at: { type: string, format: date-time, nullable: true, description: 烤制完成时间，分批传菜排序依据 }
        unit: { type: string, nullable: true }
        wait_seconds: { type: integer }
        overdue_flag: { type: boolean }
        rush_flag: { type: integer, enum: [0, 1] }
        add_dish_flag: { type: integer, enum: [0, 1], description: '加菜轮次' }
        hold_flag: { type: integer, enum: [0, 1], description: '等叫未送厨' }

    KdsExpeditionServeRequest:
      type: object
      required: [dish_name, quantity]
      properties:
        dish_name: { type: string }
        dishName: { type: string }
        quantity: { type: integer, minimum: 1 }
        qty: { type: integer, minimum: 1 }
        screen_tag: { $ref: '#/components/schemas/KdsScreenTag', description: 可选，限定荤/素/海鲜岗 }
        screenTag: { $ref: '#/components/schemas/KdsScreenTag' }

    KdsExpeditionServeResponse:
      type: object
      properties:
        dish_name: { type: string }
        screen_tag: { $ref: '#/components/schemas/KdsScreenTag', nullable: true }
        requested: { type: integer }
        served: { type: integer }
        updated_lines: { type: integer }
        remaining_quantity: { type: integer, description: 该菜品传菜后全店待传剩余合计 }

"""

marker = "\n    KdsGrillBoardResponse:\n"
if marker not in text:
    raise SystemExit("KdsGrillBoardResponse marker not found")
text = text.replace(marker, BLOCK + marker, 1)
PATH.write_text(text, encoding="utf-8", newline="\n")
print("inserted KdsOverview schemas, count:", text.count("KdsOverviewBoardResponse"))
