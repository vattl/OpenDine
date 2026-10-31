import { getCurrentShopId } from "./shopContext.js";

/** 活动轮播本地缓存键（按当前门店隔离） */
export function activityCarouselStorageKey(baseKey) {
  const shopId = Number(getCurrentShopId());
  const sid = Number.isFinite(shopId) && shopId > 0 ? shopId : 0;
  return `${baseKey}_shop_${sid}`;
}
