/**
 * 球面距离（km），经纬度为 WGS84/ GCJ-02 均按角度计算
 */
export function distanceKm(lat1, lng1, lat2, lng2) {
  const a1 = Number(lat1);
  const o1 = Number(lng1);
  const a2 = Number(lat2);
  const o2 = Number(lng2);
  if (![a1, o1, a2, o2].every((n) => Number.isFinite(n))) {
    return NaN;
  }
  const toRad = (d) => (d * Math.PI) / 180;
  const R = 6371;
  const dLat = toRad(a2 - a1);
  const dLng = toRad(o2 - o1);
  const c =
    Math.sin(dLat / 2) * Math.sin(dLat / 2) +
    Math.cos(toRad(a1)) * Math.cos(toRad(a2)) * Math.sin(dLng / 2) * Math.sin(dLng / 2);
  return R * 2 * Math.atan2(Math.sqrt(c), Math.sqrt(1 - c));
}

/**
 * 解析门店经纬度（与 openapi Shop 常见字段一致）
 * @param {object} shop
 * @returns {{ lat: number, lng: number } | null}
 */
function shopLatLng(shop) {
  if (!shop) return null;
  const la = shop.latitude;
  const lo = shop.longitude;
  const altLat = la != null ? la : shop.lat;
  const altLng = lo != null ? lo : shop.lng;
  const lat = Number(altLat);
  const lng = Number(altLng);
  if (!Number.isFinite(lat) || !Number.isFinite(lng)) return null;
  if (Math.abs(lat) < 1e-6 && Math.abs(lng) < 1e-6) return null;
  return { lat, lng };
}

/**
 * 从营业列表中选取与当前用户坐标直线距离最近的门店
 * @param {object[]} shops
 * @param {{ latitude: number, longitude: number }} user
 * @returns {object | null}
 */
export function findNearestShop(shops, user) {
  if (!Array.isArray(shops) || !user) return null;
  const uLat = Number(user.latitude);
  const uLng = Number(user.longitude);
  if (!Number.isFinite(uLat) || !Number.isFinite(uLng)) return null;
  let best = null;
  let bestD = Infinity;
  shops.forEach((s) => {
    const pos = shopLatLng(s);
    if (!pos) return;
    const d = distanceKm(uLat, uLng, pos.lat, pos.lng);
    if (!Number.isFinite(d) || d < 0) return;
    if (d < bestD) {
      bestD = d;
      best = s;
    }
  });
  return best;
}

/**
 * 用户到指定门店的直线距离（km），用于展示
 * @param {{ latitude: number, longitude: number } | null} user
 * @param {object} shop
 * @returns {number | null}
 */
export function distanceUserToShopKm(user, shop) {
  if (!user) return null;
  const uLat = Number(user.latitude);
  const uLng = Number(user.longitude);
  const pos = shopLatLng(shop);
  if (!Number.isFinite(uLat) || !Number.isFinite(uLng) || !pos) return null;
  const d = distanceKm(uLat, uLng, pos.lat, pos.lng);
  return Number.isFinite(d) && d >= 0 ? d : null;
}
