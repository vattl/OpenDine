/**
 * 打包/外卖打包费：商品金额每满 100 元收 1 元，不足 100 元也按 1 元计。
 */

export const PACKAGING_STEP_YUAN = 100;
export const PACKAGING_UNIT_FEE_YUAN = 1;

export function needsPackagingFee(dineInOrTakeOut) {
  const mode = String(dineInOrTakeOut || "").trim();
  return mode === "打包" || mode === "外卖";
}

/**
 * @param {number} goodsTotalYuan 商品小计（不含打包费）
 * @returns {{ boxCount: number, fee: number }}
 */
export function calcPackagingFee(goodsTotalYuan) {
  const goods = Number(goodsTotalYuan);
  if (!Number.isFinite(goods) || goods <= 0) {
    return { boxCount: 0, fee: 0 };
  }
  const boxCount = Math.max(Math.ceil(goods / PACKAGING_STEP_YUAN), 1);
  const fee = Math.round(boxCount * PACKAGING_UNIT_FEE_YUAN * 100) / 100;
  return { boxCount, fee };
}

export function getPackagingFeeHintText() {
  return `每满${PACKAGING_STEP_YUAN}元收${PACKAGING_UNIT_FEE_YUAN}元，不足${PACKAGING_STEP_YUAN}元按${PACKAGING_UNIT_FEE_YUAN}元计`;
}
