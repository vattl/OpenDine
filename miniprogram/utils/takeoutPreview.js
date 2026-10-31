/**
 * 外卖配送预览（POST /order/takeout/preview）与规则文案
 * @see miniprogram/docs/openapi.yaml v1.2.40
 */

/** 默认规则说明（与门店默认配置一致，接口未返回 tiers 时兜底） */
export const DEFAULT_TAKEOUT_DELIVERY_RULES_LINES = [
  "起送门槛 68 元（按配送距离收费）",
  "1–3km：5 元；3–4km：8 元；4–5km：10 元",
  "商品满 168 元且 5 公里内免配送费",
];

export function getDefaultTakeoutDeliveryRulesText() {
  return DEFAULT_TAKEOUT_DELIVERY_RULES_LINES.join("\n");
}

function parseJsonArray(raw) {
  if (Array.isArray(raw)) return raw;
  if (typeof raw === "string" && raw.trim()) {
    try {
      const parsed = JSON.parse(raw);
      return Array.isArray(parsed) ? parsed : [];
    } catch (e) {
      return [];
    }
  }
  return [];
}

/**
 * 将阶梯配置格式化为展示文案
 * @param {Array|object|string} tiers
 */
export function formatDeliveryFeeTiersText(tiers) {
  const list = parseJsonArray(tiers);
  if (!list.length) return getDefaultTakeoutDeliveryRulesText();

  const lines = [];
  list.forEach((tier, idx) => {
    if (!tier || typeof tier !== "object") return;
    const fee = Number(tier.fee ?? tier.delivery_fee ?? tier.amount);
    const feeText = Number.isFinite(fee) ? `¥${fee}` : "";
    const minKm = tier.min_km ?? tier.minKm ?? tier.from_km;
    const maxKm = tier.max_km ?? tier.maxKm ?? tier.to_km ?? tier.distance_km;
    let range = "";
    if (minKm != null && maxKm != null) {
      range = `${minKm}–${maxKm}km`;
    } else if (maxKm != null) {
      range = `≤${maxKm}km`;
    } else if (minKm != null) {
      range = `≥${minKm}km`;
    } else if (tier.label) {
      range = String(tier.label);
    } else {
      range = `第${idx + 1}档`;
    }
    if (feeText) lines.push(`${range}：${feeText}`);
  });
  return lines.length ? lines.join("；") : getDefaultTakeoutDeliveryRulesText();
}

function isTruthyFlag(v) {
  return v === true || v === 1 || v === "1" || v === "true";
}

function isFalsyFlag(v) {
  return v === false || v === 0 || v === "0" || v === "false";
}

/**
 * 解析 preview / config 响应中的配送相关字段
 * @param {object} res requestUtil 返回体（含 code、data）
 * @param {{ goodsSubtotal?: number }} options
 */
export function normalizeTakeoutPreviewPayload(res, options = {}) {
  const body =
    res && res.data != null && typeof res.data === "object" && !Array.isArray(res.data)
      ? res.data
      : res && typeof res === "object"
        ? res
        : {};

  const goodsSub = Number(options.goodsSubtotal);
  const feeRaw = Number(body.delivery_fee ?? body.deliveryFee ?? 0);
  const freeDelivery =
    isTruthyFlag(body.free_delivery) || isTruthyFlag(body.freeDelivery);
  const deliveryFee = freeDelivery
    ? 0
    : Math.round((Number.isFinite(feeRaw) ? feeRaw : 0) * 100) / 100;

  let deliverable = true;
  if (isFalsyFlag(body.deliverable)) deliverable = false;

  const distanceRaw = body.distance_km ?? body.distanceKm;
  const distanceKm =
    distanceRaw != null && distanceRaw !== "" && Number.isFinite(Number(distanceRaw))
      ? Math.round(Number(distanceRaw) * 100) / 100
      : null;

  const minAmt = Number(body.min_order_amount ?? body.minOrderAmount ?? NaN);
  const minOrderAmount = Number.isFinite(minAmt) && minAmt >= 0 ? minAmt : null;

  let meetMinOrderOk = true;
  const meet = body.meet_min_order ?? body.meetMinOrder;
  if (isFalsyFlag(meet)) meetMinOrderOk = false;
  else if (isTruthyFlag(meet)) meetMinOrderOk = true;
  else if (minOrderAmount != null && Number.isFinite(goodsSub)) {
    meetMinOrderOk = goodsSub + 1e-6 >= minOrderAmount;
  }

  const tiersRaw =
    body.delivery_fee_tiers ??
    body.deliveryFeeTiers ??
    body.delivery_fee_tiers_json ??
    body.deliveryFeeTiersJson;

  const undeliverableMsg =
    body.undeliverable_reason ??
    body.undeliverableReason ??
    (deliverable
      ? ""
      : distanceKm != null
        ? `超出配送范围（约 ${distanceKm} km）`
        : "超出配送范围，请更换地址");

  const freeThreshold = Number(
    body.free_delivery_threshold ??
      body.freeDeliveryThreshold ??
      body.free_delivery_goods_threshold ??
      168
  );

  return {
    deliveryFee,
    freeDelivery,
    deliverable,
    distanceKm,
    minOrderAmount,
    meetMinOrderOk,
    deliveryFeeTiers: parseJsonArray(tiersRaw),
    deliveryRulesText: formatDeliveryFeeTiersText(tiersRaw),
    undeliverableMsg,
    freeDeliveryThreshold: Number.isFinite(freeThreshold) ? freeThreshold : 168,
  };
}

/**
 * 从 GET /order/takeout/config 的 config 解析规则文案与起送价
 */
export function normalizeTakeoutConfigPayload(res) {
  const raw = (res && res.data) || res;
  const cfg = (raw && raw.config) || raw || {};
  const enabled =
    cfg.enabled === 1 || cfg.enabled === true || String(cfg.enabled) === "1";
  const min = Number(cfg.min_order_amount ?? cfg.minOrderAmount ?? 68);
  const tiersRaw =
    cfg.delivery_fee_tiers ??
    cfg.deliveryFeeTiers ??
    cfg.delivery_fee_tiers_json ??
    cfg.deliveryFeeTiersJson;

  return {
    enabled,
    minOrderAmount: Number.isFinite(min) ? min : 68,
    deliveryRulesText: formatDeliveryFeeTiersText(tiersRaw),
    freeDeliveryThreshold: Number(
      cfg.free_delivery_threshold ?? cfg.freeDeliveryThreshold ?? 168
    ),
  };
}
