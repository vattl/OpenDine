import { requestUtil } from "./requestUtil.js";
import { getCurrentShopId } from "./shopContext.js";

/** 与 `POST /order/recharge` 金额范围（C 端最低 50、最高 10000，需与服务端校验一致） */
export const RECHARGE_AMOUNT_MIN = 50;
export const RECHARGE_AMOUNT_MAX = 10000;

/**
 * 与 openapi 固定充送档一致（POST /order/recharge 强校验）；含无赠送的常用预设（如 100）
 * @type {{ amount: number, gift: number }[]}
 */
export const RECHARGE_GIFT_TIERS = [
  { amount: 100, gift: 0 },
  { amount: 200, gift: 10 },
  { amount: 500, gift: 50 },
  { amount: 1000, gift: 120 },
  { amount: 5000, gift: 750 },
  { amount: 10000, gift: 2000 },
];

export function normalizeRechargeAmountYuan(y) {
  const n = Number(y);
  if (!Number.isFinite(n)) return null;
  return Math.round(n * 100) / 100;
}

/**
 * 本金命中活动档时返回赠送（元），否则 0（与 openapi：不传/0 表示不要赠送）
 * @param {number} y
 * @returns {number}
 */
export function giftForRechargeAmountYuan(y) {
  const n = normalizeRechargeAmountYuan(y);
  if (n == null || n <= 0) return 0;
  const hit = RECHARGE_GIFT_TIERS.find((t) => Math.abs(t.amount - n) < 1e-6);
  return hit ? hit.gift : 0;
}

/** 赠送金额序列化为接口字符串（元） */
function giftYuanToApiString(giftYuan) {
  const g = normalizeRechargeAmountYuan(giftYuan);
  if (g == null || g <= 0) return null;
  return Number.isInteger(g) ? String(g) : (Math.round(g * 100) / 100).toFixed(2);
}

/**
 * C 端会员微信充值：先 `POST /order/recharge`，若换单无 payParams，则仅用 `POST /order/getPrepayId` 续拉（勿重复 recharge）。
 * 请求体与 openapi 对齐：`openid`、`amount`（元字符串）、可选 `gift_amount`（本金命中活动档时自动带上）、可选 `takeOut`、`shop_id`。
 * @param {{ openid: string, amountYuan: number, takeOut?: string }} p
 * @returns {Promise<any>} 与 getPrepayId 成功体一致时含 payParams
 */
export async function rechargeCreateAndGetPayParams({ openid, amountYuan, takeOut = "" }) {
  const amount = normalizeRechargeAmountYuan(amountYuan);
  if (amount == null || amount < RECHARGE_AMOUNT_MIN || amount > RECHARGE_AMOUNT_MAX) {
    return {
      code: -1,
      msg: `充值金额须在 ${RECHARGE_AMOUNT_MIN}～${RECHARGE_AMOUNT_MAX} 元之间`,
    };
  }
  const amountStr = String(amount);
  const giftStr = giftYuanToApiString(giftForRechargeAmountYuan(amount));

  /** @type {Record<string, string>} */
  const payload = { openid, amount: amountStr };
  if (giftStr != null) {
    payload.gift_amount = giftStr;
  }
  if (takeOut != null && String(takeOut).trim() !== "") {
    payload.takeOut = String(takeOut);
  }
  const sid = getCurrentShopId();
  if (sid != null && sid > 0) {
    payload.shop_id = String(sid);
  }

  const first = await requestUtil({
    url: "/order/recharge",
    method: "post",
    data: payload,
    showLoading: false,
  });
  if (!first || first.code !== 0) return first;
  if (first.payParams) return first;

  const orderNo = first.newOrderNo || first.orderNo;
  if (!orderNo) return first;

  const payData = {
    orderNo,
    openid,
    totalAmount: amountStr,
    takeOut: takeOut != null ? String(takeOut) : "",
    coupon_id: "",
    coupon_type: "",
    discount_amount: 0,
  };

  let prep = await requestUtil({
    url: "/order/getPrepayId",
    method: "post",
    data: payData,
    showLoading: false,
  });
  let guard = 0;
  while (prep && prep.code === 0 && prep.newOrderNo && !prep.payParams && guard < 5) {
    guard += 1;
    payData.orderNo = prep.newOrderNo;
    prep = await requestUtil({
      url: "/order/getPrepayId",
      method: "post",
      data: payData,
      showLoading: false,
    });
  }
  return prep;
}
