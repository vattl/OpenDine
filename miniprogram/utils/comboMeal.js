import { requestUtil } from "./requestUtil.js";
import { dishOnShelf, dishSoldOut } from "./dishSale.js";
import { serializeSelectedSpicy } from "./dishSpecification.js";

/** 购物车/订单行是否为套餐（头行） */
export function isComboCartLine(item) {
  if (!item || typeof item !== "object") return false;
  if (item.isCombo === true) return true;
  const lt = String(item.line_type || item.lineType || "").toLowerCase();
  if (lt === "combo" || lt === "combo_header") return true;
  const cid = item.combo_id != null ? item.combo_id : item.comboId;
  return normId(cid) != null;
}

/** 列表中是否含套餐行（含已落库的 combo_header） */
export function cartHasComboLines(lines) {
  if (!Array.isArray(lines)) return false;
  return lines.some(isComboCartLine);
}

/** 套餐订单不可用优惠券/余额时的提示文案 */
export const COMBO_PAYMENT_RESTRICT_MSG =
  "套餐不参与任何优惠活动";

/** 菜单项是否为套餐头菜（listAll 附带 comboDefinition） */
export function isComboDish(dish) {
  if (!dish || typeof dish !== "object") return false;
  if (dish.isCombo === true) return true;
  const def = dish.comboDefinition;
  if (!def || typeof def !== "object") return false;
  const cid = def.comboId != null ? def.comboId : def.combo_id;
  if (cid != null && Number(cid) > 0) return true;
  const fixed = def.fixedItems || def.fixed_items || [];
  const groups = def.groups || [];
  return (Array.isArray(fixed) && fixed.length > 0) || (Array.isArray(groups) && groups.length > 0);
}

function normId(v) {
  const n = Number(v);
  return Number.isFinite(n) && n > 0 ? n : null;
}

/** 子菜 dishId（v1.2.39 ComboCustomerDishItem 用 dishId；listAll/运营定义用 componentDishId） */
export function componentDishId(item) {
  if (!item) return null;
  return normId(
    item.dishId != null
      ? item.dishId
      : item.componentDishId != null
        ? item.componentDishId
        : item.component_dish_id || item.dish_id
  );
}

function componentViewName(item) {
  if (!item) return "";
  return String(item.name || item.dishName || "").trim();
}

function normalizeSpecificationValue(value) {
  if (value == null || value === "") return "";
  if (typeof value === "string") return value;
  if (typeof value === "object" && !Array.isArray(value)) return value;
  return String(value);
}

export function componentCanPick(item) {
  if (!item) return false;
  if (dishSoldOut(item)) return false;
  return dishOnShelf(item);
}

function normalizeDishItem(raw) {
  if (!raw || typeof raw !== "object") return null;
  const dishId = componentDishId(raw);
  if (!dishId) return null;
  return {
    dishId,
    name: componentViewName(raw),
    image: raw.image || "",
    unit: raw.unit || "份",
    unitprice: Number(raw.unitprice != null ? raw.unitprice : raw.unit_price) || 0,
    stock: raw.stock,
    onsale: raw.onsale !== false,
    sold_out: raw.sold_out,
    qtyPerCombo: Number(raw.qtyPerCombo != null ? raw.qtyPerCombo : raw.qty_per_combo) || 1,
    extraPrice: Number(raw.extraPrice != null ? raw.extraPrice : raw.extra_price) || 0,
    specification: normalizeSpecificationValue(raw.specification),
  };
}

function normalizeGroup(g) {
  if (!g || typeof g !== "object") return null;
  const groupKey = g.groupKey || g.group_key;
  if (!groupKey) return null;
  const minPick = Math.max(0, Number(g.minPick != null ? g.minPick : g.min_pick) || 0);
  const maxPick = Math.max(
    minPick,
    Number(g.maxPick != null ? g.maxPick : g.max_pick) || 1
  );
  const optionSrc = g.options || g.items || [];
  const options = (Array.isArray(optionSrc) ? optionSrc : [])
    .map(normalizeDishItem)
    .filter(Boolean);
  return { groupKey, title: g.title || groupKey, minPick, maxPick, options };
}

/**
 * 将 GET /combo/detail 响应规范为 ComboCustomerDetail（v1.2.39+）
 * 兼容旧版 definition + headerDish 结构
 */
export function normalizeComboCustomerDetail(body) {
  if (!body || typeof body !== "object") return null;

  const comboId = normId(body.comboId != null ? body.comboId : body.combo_id);
  const dishId = normId(body.dishId != null ? body.dishId : body.dish_id);
  const comboType = body.comboType || body.combo_type || "";
  const message = body.message != null ? String(body.message) : "";

  let configured = body.configured;
  if (configured === undefined && comboId) configured = true;
  if (configured === 0 || configured === "0" || configured === false) configured = false;
  else if (configured === 1 || configured === "1" || configured === true) configured = true;

  const baseUnitPrice = Number(
    body.baseUnitPrice != null ? body.baseUnitPrice : body.base_unit_price
  );
  const originalUnitPrice = Number(
    body.originalUnitPrice != null
      ? body.originalUnitPrice
      : body.original_unit_price
  );

  let headerRaw = body.header || body.headerDish || body.header_dish || null;
  const definition = body.definition;

  if (!headerRaw && definition && dishId) {
    headerRaw = { dishId, name: "", unitprice: baseUnitPrice };
  }

  let header = normalizeDishItem(headerRaw);
  if (!header && dishId) {
    header = {
      dishId,
      name: "",
      image: "",
      unit: "份",
      unitprice: Number.isFinite(baseUnitPrice) ? baseUnitPrice : 0,
      onsale: true,
      sold_out: 0,
      qtyPerCombo: 1,
      extraPrice: 0,
    };
  }

  let fixedItems = [];
  let groups = [];

  if (Array.isArray(body.fixedItems)) {
    fixedItems = body.fixedItems.map(normalizeDishItem).filter(Boolean);
  } else if (definition && Array.isArray(definition.fixedItems || definition.fixed_items)) {
    fixedItems = (definition.fixedItems || definition.fixed_items)
      .map(normalizeDishItem)
      .filter(Boolean);
  }

  if (Array.isArray(body.groups)) {
    groups = body.groups.map(normalizeGroup).filter(Boolean);
  } else if (definition && Array.isArray(definition.groups)) {
    groups = definition.groups.map(normalizeGroup).filter(Boolean);
  }

  if (configured !== false && comboId && header) {
    configured = true;
  }

  return {
    configured: configured === true,
    comboId,
    dishId: dishId || (header && header.dishId),
    comboType,
    baseUnitPrice: Number.isFinite(baseUnitPrice)
      ? baseUnitPrice
      : header
        ? header.unitprice
        : 0,
    originalUnitPrice: Number.isFinite(originalUnitPrice) ? originalUnitPrice : undefined,
    header,
    fixedItems,
    groups,
    message,
  };
}

/** 解析 GET /combo/detail（字段可在 data 或顶层） */
export function parseComboDetailResponse(res) {
  if (!res || res.code !== 0) {
    return {
      ok: false,
      message: (res && (res.msg || res.message)) || "套餐加载失败",
    };
  }
  const body = res.data != null && typeof res.data === "object" ? res.data : res;
  const detail = normalizeComboCustomerDetail(body);

  if (!detail) {
    return { ok: false, message: "套餐数据异常" };
  }

  if (detail.configured === false || !detail.comboId || !detail.header) {
    return {
      ok: false,
      message: detail.message || "该菜品暂未配置套餐",
    };
  }

  return {
    ok: true,
    ...detail,
    /** @deprecated 仅兼容旧代码，请用 header / fixedItems / groups */
    definition: {
      comboId: detail.comboId,
      dishId: detail.dishId,
      comboType: detail.comboType,
      fixedItems: detail.fixedItems,
      groups: detail.groups.map((g) => ({
        groupKey: g.groupKey,
        title: g.title,
        minPick: g.minPick,
        maxPick: g.maxPick,
        items: g.options,
      })),
    },
    headerDish: detail.header,
  };
}

export async function fetchComboDetail(dishId) {
  const id = normId(dishId);
  if (!id) return { ok: false, message: "菜品参数无效" };
  const res = await requestUtil({
    url: `/combo/detail?dishId=${id}`,
    method: "get",
    showLoading: true,
  });
  return parseComboDetailResponse(res);
}

/** 组内默认选中 */
export function buildDefaultComboSelections(detail) {
  const selections = {};
  const groups = (detail && detail.groups) || [];
  groups.forEach((g) => {
    const key = g.groupKey;
    if (!key) return;
    const minPick = g.minPick;
    const maxPick = g.maxPick;
    const items = (g.options || []).filter(componentCanPick);
    const picked = [];
    for (let i = 0; i < items.length && picked.length < maxPick; i++) {
      const did = componentDishId(items[i]);
      if (did && !picked.includes(did)) picked.push(did);
    }
    while (picked.length < minPick && items.length > picked.length) {
      for (const it of items) {
        const did = componentDishId(it);
        if (did && !picked.includes(did)) {
          picked.push(did);
          break;
        }
      }
      if (picked.length >= minPick) break;
    }
    if (picked.length) selections[key] = picked;
  });
  return selections;
}

export function validateComboSelections(detail, selections) {
  const groups = (detail && detail.groups) || [];
  for (const g of groups) {
    const key = g.groupKey;
    if (!key) continue;
    const minPick = g.minPick;
    const maxPick = g.maxPick;
    const picked = Array.isArray(selections[key]) ? selections[key] : [];
    const title = g.title || key;
    if (picked.length < minPick) {
      return { ok: false, message: `「${title}」至少选择 ${minPick} 项` };
    }
    if (picked.length > maxPick) {
      return { ok: false, message: `「${title}」最多选择 ${maxPick} 项` };
    }
    const allowed = new Set((g.options || []).map(componentDishId).filter(Boolean));
    for (const id of picked) {
      if (!allowed.has(Number(id))) {
        return { ok: false, message: `「${title}」含无效选项` };
      }
      const item = (g.options || []).find((it) => componentDishId(it) === Number(id));
      if (item && !componentCanPick(item)) {
        return { ok: false, message: `「${componentViewName(item) || title}」已售罄或下架` };
      }
    }
  }
  return { ok: true };
}

/**
 * 套餐「原价」单价：优先接口字段，否则按当前选中的子菜单价合计（分开点单口径）
 */
export function computeComboOriginalUnitPrice(detail, selections) {
  if (!detail || typeof detail !== "object") return 0;
  const apiVal = Number(
    detail.originalUnitPrice != null
      ? detail.originalUnitPrice
      : detail.original_unit_price
  );
  if (Number.isFinite(apiVal) && apiVal > 0) {
    return Math.round(apiVal * 100) / 100;
  }

  let sum = 0;
  (detail.fixedItems || []).forEach((it) => {
    const p = Number(it.unitprice) || 0;
    const q = Number(it.qtyPerCombo) || 1;
    sum += p * q;
  });
  (detail.groups || []).forEach((g) => {
    const key = g.groupKey;
    const ids = (selections && selections[key]) || [];
    const priceMap = {};
    (g.options || []).forEach((it) => {
      const did = componentDishId(it);
      if (did) priceMap[did] = Number(it.unitprice) || 0;
    });
    ids.forEach((id) => {
      sum += priceMap[Number(id)] || 0;
    });
  });
  if (sum > 0) return Math.round(sum * 100) / 100;

  const header = detail.header || detail.headerDish || {};
  const headerP = Number(header.unitprice);
  if (Number.isFinite(headerP) && headerP > 0) return Math.round(headerP * 100) / 100;
  return 0;
}

export async function calcComboPrice({ comboId, quantity, comboSelections }) {
  const cid = normId(comboId);
  if (!cid) return { ok: false, message: "套餐无效" };
  const qty = Math.max(1, Number(quantity) || 1);
  const res = await requestUtil({
    url: "/combo/calcPrice",
    method: "post",
    data: {
      comboId: cid,
      quantity: qty,
      combo_selections: comboSelections || {},
    },
    showLoading: false,
  });
  if (!res || res.code !== 0) {
    return {
      ok: false,
      message: (res && (res.msg || res.message)) || "价格试算失败",
    };
  }
  const tp = Number(res.total_price != null ? res.total_price : res.totalPrice);
  if (!Number.isFinite(tp)) {
    return { ok: false, message: "价格试算结果异常" };
  }
  const op = Number(
    res.original_price != null
      ? res.original_price
      : res.originalPrice != null
        ? res.originalPrice
        : res.original_total_price != null
          ? res.original_total_price
          : res.originalTotalPrice
  );
  const out = {
    ok: true,
    total_price: Math.round(tp * 100) / 100,
    comboId: cid,
    quantity: qty,
  };
  if (Number.isFinite(op) && op > 0) {
    out.original_price = Math.round(op * 100) / 100;
  }
  return out;
}

/** 选择摘要，用于购物车展示 */
export function formatComboSelectionSummary(detail, selections) {
  const parts = [];
  const fixed = (detail && detail.fixedItems) || [];
  fixed.forEach((it) => {
    const name = componentViewName(it);
    const q = Number(it.qtyPerCombo) || 1;
    if (name) parts.push(q > 1 ? `${name}×${q}` : name);
  });
  const groups = (detail && detail.groups) || [];
  groups.forEach((g) => {
    const key = g.groupKey;
    const ids = (selections && selections[key]) || [];
    const map = {};
    (g.options || []).forEach((it) => {
      const did = componentDishId(it);
      if (did) map[did] = componentViewName(it);
    });
    ids.forEach((id) => {
      const name = map[Number(id)];
      if (name) parts.push(name);
    });
  });
  return parts.join("、");
}

function stableSelectedSpicyKey(selectedSpicy) {
  if (!selectedSpicy || typeof selectedSpicy !== "object") return "";
  const keys = Object.keys(selectedSpicy).sort();
  const payload = {};
  keys.forEach((k) => {
    payload[k] = String(selectedSpicy[k] || "");
  });
  return JSON.stringify(payload);
}

export function comboSelectionsCartKey(comboId, selections, selectedSpicy) {
  const keys = Object.keys(selections || {}).sort();
  const payload = {};
  keys.forEach((k) => {
    payload[k] = [...(selections[k] || [])].map(Number).sort((a, b) => a - b);
  });
  const specPart = stableSelectedSpicyKey(selectedSpicy);
  return `combo_${comboId}_${JSON.stringify(payload)}_s${specPart}`;
}

export function buildComboCartItem({
  dish,
  detail,
  selections,
  quantity,
  totalPrice,
  catIndex,
  dishIndex,
  cid,
  selectedSpicy,
}) {
  const comboId = detail.comboId;
  const qty = Math.max(1, Number(quantity) || 1);
  const tp = Math.round(Number(totalPrice) * 100) / 100;
  const header = detail.header || detail.headerDish || {};
  const unitprice =
    Number(detail.baseUnitPrice != null ? detail.baseUnitPrice : header.unitprice) || 0;
  const summary = formatComboSelectionSummary(detail, selections);
  const spicySerialized =
    typeof selectedSpicy === "string"
      ? selectedSpicy
      : serializeSelectedSpicy(selectedSpicy);
  const cartKey = comboSelectionsCartKey(comboId, selections, selectedSpicy);
  return {
    line_type: "combo",
    isCombo: true,
    combo_id: comboId,
    combo_selections: { ...selections },
    comboSummary: summary,
    cartKey,
    id: detail.dishId || header.dishId || dish.id,
    name: header.name || dish.name,
    image: header.image || dish.image,
    unit: header.unit || dish.unit || "份",
    unitprice,
    quantity: qty,
    total_price: tp,
    cid: String(cid != null ? cid : ""),
    index: catIndex,
    good_index: dishIndex,
    onsale: header.onsale !== false && dish.onsale !== false,
    sold_out: header.sold_out != null ? header.sold_out : dish.sold_out,
    selectedSpicy: spicySerialized || "",
  };
}

export function mapCartItemToOrderLine(item) {
  if (!item) return null;
  const qty = Math.max(1, Number(item.quantity) || 1);
  const base = {
    name: item.name,
    quantity: String(qty),
    unit: item.unit || "份",
    image: item.image,
    total_price: Math.round(Number(item.total_price || 0) * 100) / 100,
    cid: item.cid != null ? String(item.cid) : "",
    remark: item.remark || "",
    selectedSpicy: item.selectedSpicy || "",
  };
  if (item.isCombo || item.combo_id || item.line_type === "combo") {
    return {
      ...base,
      line_type: "combo",
      combo_id: Number(item.combo_id),
      combo_selections: item.combo_selections || {},
    };
  }
  return base;
}

export function mapCartToGoodsList(cart) {
  if (!Array.isArray(cart)) return [];
  return cart
    .filter((row) => row && Number(row.quantity) > 0)
    .map(mapCartItemToOrderLine)
    .filter(Boolean);
}

export async function recalcComboCartLineTotal(line) {
  if (!line || !line.combo_id) return line;
  const qty = Math.max(1, Number(line.quantity) || 1);
  const pr = await calcComboPrice({
    comboId: line.combo_id,
    quantity: qty,
    comboSelections: line.combo_selections,
  });
  if (!pr.ok) return line;
  return {
    ...line,
    quantity: qty,
    total_price: pr.total_price,
  };
}

/** 订单明细：套餐头行 */
export function isComboHeaderOrderLine(item) {
  if (!item || typeof item !== "object") return false;
  const lt = String(item.line_type || item.lineType || "").toLowerCase();
  return lt === "combo_header" || lt === "combo";
}

/** 订单明细：套餐子菜行 */
export function isComboComponentOrderLine(item) {
  if (!item || typeof item !== "object") return false;
  const lt = String(item.line_type || item.lineType || "").toLowerCase();
  return lt === "combo_component";
}

function orderDetailLineId(line) {
  const n = Number(
    line && (line.id != null ? line.id : line.detail_id != null ? line.detail_id : line.detailId)
  );
  return Number.isFinite(n) && n > 0 ? Math.floor(n) : null;
}

function parseComboSelectionJson(raw) {
  if (raw == null || raw === "") return null;
  try {
    const v = typeof raw === "string" ? JSON.parse(raw) : raw;
    return v && typeof v === "object" ? v : null;
  } catch (e) {
    return null;
  }
}

/** 从订单 goods_list 中取出某套餐头行对应的子菜明细 */
export function getComboComponentsForOrderHeader(header, goodsList) {
  if (!header || !Array.isArray(goodsList)) return [];
  const headerId = orderDetailLineId(header);
  const instanceId = String(
    header.combo_instance_id || header.comboInstanceId || ""
  ).trim();
  const out = [];
  goodsList.forEach((row) => {
    if (!isComboComponentOrderLine(row)) return;
    const parentId = Number(row.parent_detail_id ?? row.parentDetailId);
    const rowInstance = String(
      row.combo_instance_id || row.comboInstanceId || ""
    ).trim();
    let match = false;
    if (headerId && Number.isFinite(parentId) && parentId === headerId) {
      match = true;
    } else if (instanceId && rowInstance && rowInstance === instanceId) {
      match = true;
    }
    if (!match) return;
    const name = String(row.name || "").trim() || "菜品";
    const qty = Math.max(1, Number(row.quantity) || 1);
    out.push({
      name,
      quantity: qty,
      unit: row.unit || "份",
    });
  });
  return out;
}

function fallbackItemsFromSelectionJson(header) {
  const sel = parseComboSelectionJson(
    header && (header.combo_selection_json || header.comboSelectionJson)
  );
  if (!sel) return [];
  const items = [];
  Object.keys(sel).forEach((key) => {
    const arr = sel[key];
    if (!Array.isArray(arr) || !arr.length) return;
    items.push({
      name: `已选菜品（${arr.length}项）`,
      quantity: 1,
      unit: "组",
      groupKey: key,
    });
  });
  return items;
}

/**
 * 订单详情页：套餐头行展示数据（子菜列表 + 摘要）
 * @returns {{ title: string, items: Array<{name,quantity,unit}>, summary: string, hasDetail: boolean }}
 */
export function buildOrderComboDetailView(header, goodsList) {
  const title = String((header && header.name) || "").trim() || "套餐";
  let items = getComboComponentsForOrderHeader(header, goodsList);
  if (!items.length) {
    items = fallbackItemsFromSelectionJson(header);
  }
  const headerQty = Math.max(1, Number(header && header.quantity) || 1);
  const summaryParts = items.map((it) =>
    it.quantity > 1 ? `${it.name}×${it.quantity}` : it.name
  );
  let summary = summaryParts.join("、");
  if (headerQty > 1) {
    summary = summary
      ? `${summary}（套餐×${headerQty}）`
      : `套餐×${headerQty}`;
  }
  return {
    title,
    items,
    summary,
    hasDetail: items.length > 0,
  };
}
