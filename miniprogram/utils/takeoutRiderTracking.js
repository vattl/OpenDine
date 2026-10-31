/**
 * 外卖真省钱骑手追踪（C 端 GET /order/takeout/order/tracking）
 * 响应结构见 openapi ZsqRiderTrackingResponse / TakeoutDelivery.zsq_rider_*
 */
import { distanceKm } from "./geoDistance.js";

const PHASE_LABEL = {
  WAITING_RIDER: "待骑手接单",
  TO_SHOP: "骑手赶往商家",
  TO_USER: "骑手配送中",
  DELIVERED: "已送达",
  CANCELLED: "配送已取消",
  UNKNOWN: "配送中",
};

const DISPATCH_POLL_STATUSES = new Set([
  "accepted",
  "delivering",
  "dispatch_failed",
]);

/** 订单详情页轮询间隔（毫秒） */
export const RIDER_TRACKING_POLL_MS = 15000;

function trimStr(v) {
  return v == null ? "" : String(v).trim();
}

function validCoord(lat, lng) {
  const la = Number(lat);
  const ln = Number(lng);
  return Number.isFinite(la) && Number.isFinite(ln) && !(la === 0 && ln === 0);
}

function formatKm(km) {
  const n = Number(km);
  if (!Number.isFinite(n) || n < 0) return "";
  if (n < 1) return `${Math.max(1, Math.round(n * 1000))}米`;
  return `${n.toFixed(n >= 10 ? 0 : 1)}公里`;
}

function parseMinutesFromText(text) {
  const s = trimStr(text);
  if (!s) return null;
  const m = s.match(/(\d+)\s*分/);
  if (m) return Number(m[1]);
  const m2 = s.match(/^(\d+)$/);
  return m2 ? Number(m2[1]) : null;
}

/** 履约状态：优先 tracking.dispatchStatus（v1.2.57），其次订单/配送扩展 */
export function resolveTakeoutDispatchStatus(tracking, delivery, order) {
  const tr = tracking && typeof tracking === "object" ? tracking : {};
  const del = delivery && typeof delivery === "object" ? delivery : {};
  const o = order && typeof order === "object" ? order : {};
  return trimStr(
    tr.dispatchStatus ||
      tr.dispatch_status ||
      o.takeout_dispatch_status ||
      o.takeoutDispatchStatus ||
      del.dispatch_status ||
      del.dispatchStatus
  ).toLowerCase();
}

/** 是否应轮询骑手追踪（已发真省钱配送且仍在履约中） */
export function shouldPollTakeoutRiderTracking(delivery, order, tracking) {
  if (!delivery || typeof delivery !== "object") return false;
  const openId = delivery.zsq_open_order_id ?? delivery.zsqOpenOrderId;
  if (openId == null || openId === "") return false;
  const o = order || {};
  if (trimStr(o.transac_status).toLowerCase() !== "success") return false;

  const tr = tracking && typeof tracking === "object" ? tracking : {};
  const phase = trimStr(tr.phase).toUpperCase();
  if (phase === "DELIVERED" || phase === "CANCELLED") return false;

  const status = resolveTakeoutDispatchStatus(tracking, delivery, order);
  if (status === "completed" || status === "cancelled") return false;
  return DISPATCH_POLL_STATUSES.has(status) || status === "paid";
}

/** 外卖配送是否已完结（地图可收起，取餐码区展示已完成提示） */
export function isTakeoutDeliveryCompleted(tracking, delivery, order) {
  const tr = tracking && typeof tracking === "object" ? tracking : {};
  const phase = trimStr(tr.phase).toUpperCase();
  if (phase === "DELIVERED") return true;
  const status = resolveTakeoutDispatchStatus(tracking, delivery, order);
  return status === "completed";
}

/**
 * 合并 GET /order/takeout/order/tracking 响应（v1.2.59 含 order、delivery）
 * @returns {{ tracking: object|null, orderPatch: object|null, delivery: object|null }}
 */
export function parseTakeoutTrackingResponse(res) {
  if (!res || typeof res !== "object") {
    return { tracking: null, orderPatch: null, delivery: null };
  }
  const root = res.data != null && typeof res.data === "object" && !Array.isArray(res.data) ? res.data : res;
  const tracking =
    root.tracking && typeof root.tracking === "object"
      ? root.tracking
      : res.tracking && typeof res.tracking === "object"
        ? res.tracking
        : null;
  const orderPatch =
    root.order && typeof root.order === "object"
      ? root.order
      : res.order && typeof res.order === "object"
        ? res.order
        : null;
  const delivery =
    root.delivery && typeof root.delivery === "object"
      ? root.delivery
      : res.delivery && typeof res.delivery === "object"
        ? res.delivery
        : null;
  return { tracking, orderPatch, delivery };
}

export function takeoutPhaseLabel(phase, deliverySendStatusDesc) {
  const desc = trimStr(deliverySendStatusDesc);
  if (desc) return desc;
  const p = trimStr(phase).toUpperCase();
  return PHASE_LABEL[p] || PHASE_LABEL.UNKNOWN;
}

/** 美团式：主标题、距离、预计分钟、摘要一行 */
export function buildRiderDeliveryHero(tracking, delivery) {
  const del = delivery && typeof delivery === "object" ? delivery : {};
  const tr = tracking && typeof tracking === "object" ? tracking : {};
  const rider = tr.rider && typeof tr.rider === "object" ? tr.rider : {};
  const computed = tr.computedEta && typeof tr.computedEta === "object" ? tr.computedEta : {};
  const platform = tr.platformEta && typeof tr.platformEta === "object" ? tr.platformEta : {};

  const phase = trimStr(tr.phase || del.zsq_phase).toUpperCase();
  const phaseLabel = takeoutPhaseLabel(tr.phase || del.zsq_phase, tr.deliverySendStatusDesc);

  let headline = phaseLabel;
  if (phase === "WAITING_RIDER") headline = "正在为您呼唤骑手";
  else if (phase === "TO_SHOP") headline = "骑手正在赶往商家取餐";
  else if (phase === "TO_USER") headline = "骑手正在送货";
  else if (phase === "DELIVERED") headline = "餐品已送达";
  else if (phase === "CANCELLED") headline = "配送已取消";

  let distanceKm = null;
  let etaMinutes = null;
  let distanceLabel = "距您";
  if (phase === "TO_SHOP") {
    distanceKm = computed.riderToShopKm;
    etaMinutes = computed.toShopMinutes;
    distanceLabel = "距商家";
  } else if (phase === "TO_USER") {
    distanceKm = computed.riderToUserKm;
    etaMinutes = computed.toUserMinutes;
    distanceLabel = "距您";
  } else if (phase === "WAITING_RIDER") {
    distanceLabel = "等待接单";
  }

  let distanceText = trimStr(platform.distanceText);
  if (!distanceText && distanceKm != null && Number.isFinite(Number(distanceKm))) {
    distanceText = formatKm(distanceKm);
  }

  if (etaMinutes == null) {
    etaMinutes = parseMinutesFromText(platform.durationText);
  }

  const etaMinutesText =
    etaMinutes != null && Number.isFinite(Number(etaMinutes))
      ? String(Math.max(0, Math.round(Number(etaMinutes))))
      : "";

  const summaryParts = [];
  if (distanceText && phase !== "WAITING_RIDER" && phase !== "DELIVERED") {
    summaryParts.push(`${distanceLabel} ${distanceText}`);
  }
  if (etaMinutesText && phase !== "DELIVERED" && phase !== "CANCELLED") {
    summaryParts.push(`约 ${etaMinutesText} 分钟送达`);
  }
  const summaryLine = summaryParts.join("，");

  const name =
    trimStr(rider.name) ||
    trimStr(del.zsq_rider_name) ||
    trimStr(del.zsqRiderName);
  const phone =
    trimStr(rider.phone) ||
    trimStr(del.zsq_rider_phone) ||
    trimStr(del.zsqRiderPhone);

  let lat = rider.lat != null ? rider.lat : del.zsq_rider_lat;
  let lng = rider.lng != null ? rider.lng : del.zsq_rider_lng;

  return {
    headline,
    phaseLabel,
    phase,
    distanceLabel,
    distanceText: distanceText || (phase === "WAITING_RIDER" ? "—" : ""),
    distanceKm,
    etaMinutes,
    etaMinutesText: etaMinutesText || "—",
    summaryLine,
    name,
    phone,
    lat: validCoord(lat, lng) ? Number(lat) : null,
    lng: validCoord(lat, lng) ? Number(lng) : null,
    etaText: buildRiderEtaTextFromHero(summaryLine, platform),
  };
}

function buildRiderEtaTextFromHero(summaryLine, platform) {
  const desc = trimStr(platform && platform.description);
  if (desc) return desc;
  return summaryLine;
}

/** 从 tracking 或 delivery 合并骑手展示字段（兼容旧用法） */
export function resolveRiderDisplayInfo(tracking, delivery) {
  return buildRiderDeliveryHero(tracking, delivery);
}

/** 地图中心、markers、include-points（骑手 / 收货 / 门店） */
export function buildRiderMapState(tracking, delivery) {
  const del = delivery && typeof delivery === "object" ? delivery : {};
  const tr = tracking && typeof tracking === "object" ? tracking : {};
  const hero = buildRiderDeliveryHero(tr, del);
  const userPt = tr.user && typeof tr.user === "object" ? tr.user : {};
  const shopPt = tr.shop && typeof tr.shop === "object" ? tr.shop : {};

  const userLat =
    userPt.lat != null ? userPt.lat : del.lat != null ? del.lat : null;
  const userLng =
    userPt.lng != null ? userPt.lng : del.lng != null ? del.lng : null;

  const points = [];
  if (hero.lat != null && hero.lng != null) {
    points.push({ id: 1, lat: hero.lat, lng: hero.lng, title: "骑手", role: "rider" });
  }
  if (validCoord(userLat, userLng)) {
    points.push({
      id: 2,
      lat: Number(userLat),
      lng: Number(userLng),
      title: "收货",
      role: "user",
    });
  }
  if (validCoord(shopPt.lat, shopPt.lng)) {
    points.push({
      id: 3,
      lat: Number(shopPt.lat),
      lng: Number(shopPt.lng),
      title: "门店",
      role: "shop",
    });
  }

  if (!points.length) {
    return { center: null, markers: [], includePoints: [] };
  }

  const phase = hero.phase;
  let center = points[0];
  if (phase === "TO_USER") {
    center = points.find((p) => p.role === "user") || points.find((p) => p.role === "rider") || center;
  } else if (phase === "TO_SHOP") {
    center = points.find((p) => p.role === "rider") || points.find((p) => p.role === "shop") || center;
  } else {
    center = points.find((p) => p.role === "rider") || center;
  }

  const markers = points.map((p) => ({
    id: p.id,
    latitude: p.lat,
    longitude: p.lng,
    title: p.title,
    width: 32,
    height: 32,
    callout: {
      content: p.title,
      display: "ALWAYS",
      padding: 6,
      borderRadius: 6,
      fontSize: 12,
    },
  }));

  const includePoints = points.map((p) => ({
    latitude: p.lat,
    longitude: p.lng,
  }));

  return {
    center: { lat: center.lat, lng: center.lng },
    markers,
    includePoints,
  };
}

/** 无 tracking 时根据 delivery 缓存坐标估算距用户距离 */
export function estimateRiderDistanceToUser(tracking, delivery) {
  const hero = buildRiderDeliveryHero(tracking, delivery);
  if (hero.distanceKm != null && Number.isFinite(Number(hero.distanceKm))) {
    return formatKm(hero.distanceKm);
  }
  const del = delivery && typeof delivery === "object" ? delivery : {};
  const tr = tracking && typeof tracking === "object" ? tracking : {};
  const userPt = tr.user && typeof tr.user === "object" ? tr.user : {};
  const userLat = userPt.lat != null ? userPt.lat : del.lat;
  const userLng = userPt.lng != null ? userPt.lng : del.lng;
  if (hero.lat != null && hero.lng != null && validCoord(userLat, userLng)) {
    return formatKm(distanceKm(hero.lat, hero.lng, userLat, userLng));
  }
  return "";
}

export function hasRiderUiContent(display, mapState) {
  if (!display) return false;
  if (
    display.name ||
    display.phone ||
    display.phaseLabel ||
    display.summaryLine ||
    display.headline
  ) {
    return true;
  }
  return !!(mapState && mapState.center && mapState.markers.length);
}

export function formatRiderSyncTime(ts) {
  if (!ts) return "";
  const d = new Date(ts);
  if (Number.isNaN(d.getTime())) return "";
  const h = d.getHours();
  const m = d.getMinutes();
  const s = d.getSeconds();
  const pad = (n) => (n < 10 ? `0${n}` : `${n}`);
  return `${pad(h)}:${pad(m)}:${pad(s)}`;
}
