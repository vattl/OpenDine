/**
 * 菜品可售状态（契约：Dish.sold_out 0/1 与 onsale 独立，见 docs/openapi.yaml）
 */

export function dishSoldOut(d) {
  if (!d) return false;
  const v = d.sold_out;
  return v === 1 || v === "1" || Number(v) === 1;
}

export function dishOnShelf(d) {
  return d && d.onsale !== false;
}

/** 可点规格 / 加入购物车 */
export function dishCanOrder(d) {
  return dishOnShelf(d) && !dishSoldOut(d);
}

/** 列表展示用：规范化 sold_out 为 0 或 1 */
export function normalizeSoldOut(raw) {
  if (raw == null || raw === "") return 0;
  return Number(raw) === 1 ? 1 : 0;
}
