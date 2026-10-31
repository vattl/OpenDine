import { requestUtil } from './requestUtil.js';
import { buildDetailFromPlaceParts } from './takeoutAddressRegion.js';

const MIN_KEYWORD_LEN = 2;

function pickStr(obj, keys) {
  if (!obj || typeof obj !== 'object') return '';
  for (const k of keys) {
    const v = obj[k];
    if (v != null && String(v).trim() !== '') return String(v).trim();
  }
  return '';
}

function pickNum(obj, keys) {
  if (!obj || typeof obj !== 'object') return null;
  for (const k of keys) {
    const v = obj[k];
    if (v == null || v === '') continue;
    const n = Number(v);
    if (Number.isFinite(n)) return n;
  }
  return null;
}

/** 统一后端 / 地图 POI 候选结构 */
export function normalizeAddressSuggestItem(raw) {
  if (!raw || typeof raw !== 'object') return null;
  const title = pickStr(raw, ['title', 'name', 'poi_name', 'poiName']);
  const address = pickStr(raw, ['address', 'address_full', 'addressFull', 'full_address']);
  const detail = pickStr(raw, ['detail_address', 'detailAddress', 'detail']);
  const lat = pickNum(raw, ['lat', 'latitude']);
  const lng = pickNum(raw, ['lng', 'longitude', 'lon']);
  if (lat == null || lng == null) return null;

  const region = buildDetailFromPlaceParts({
    name: title,
    address,
    detail,
  });

  const province = pickStr(raw, ['province']) || region.province;
  const city = pickStr(raw, ['city']) || region.city;
  const district = pickStr(raw, ['district']) || region.district;
  const detailAddress = pickStr(raw, ['detail_address', 'detailAddress']) || region.detail_address;
  const addressLine = [province, city, district, detailAddress].filter(Boolean).join(' ') || address || title;

  return {
    title: title || detailAddress || addressLine,
    addressLine,
    province,
    city,
    district,
    detail_address: detailAddress,
    lat,
    lng,
  };
}

export function normalizeAddressSuggestList(res) {
  if (!res || res.code !== 0) return [];
  const data = res.data != null ? res.data : res;
  const arr = (data && (data.list || data.records || data.suggestions)) || [];
  if (!Array.isArray(arr)) return [];
  return arr.map(normalizeAddressSuggestItem).filter(Boolean);
}

/**
 * 详细地址关键词搜索（后端代理地图 POI 建议）
 * @returns {Promise<Array>}
 */
export async function fetchAddressSuggest({ keyword, province, city, district, openid }) {
  const q = String(keyword || '').trim();
  if (q.length < MIN_KEYWORD_LEN) return [];
  try {
    const res = await requestUtil({
      url: '/order/takeout/address/suggest',
      method: 'get',
      data: {
        keyword: q,
        province: province || '',
        city: city || '',
        district: district || '',
        openid: openid || '',
      },
      showLoading: false,
      showErrorMsg: false,
      timeout: 8000,
    });
    return normalizeAddressSuggestList(res);
  } catch (e) {
    return [];
  }
}

export { MIN_KEYWORD_LEN };
