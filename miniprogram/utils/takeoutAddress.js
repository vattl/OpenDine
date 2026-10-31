export const TAKEOUT_COORDINATE_TYPE = 'gcj02';

const MISSING_COORDINATE_MESSAGE = '该地址没有地图坐标，请重新选点';

function cleanText(value, maxLength = 200) {
  return String(value == null ? '' : value).trim().slice(0, maxLength);
}

export function validateGcj02Coordinates(input = {}) {
  const latRaw = input.lat != null ? input.lat : input.latitude;
  const lngRaw = input.lng != null ? input.lng : input.longitude;
  if (latRaw == null || lngRaw == null || latRaw === '' || lngRaw === '') {
    return { valid: false, reason: 'missing', message: MISSING_COORDINATE_MESSAGE };
  }

  const lat = Number(latRaw);
  const lng = Number(lngRaw);
  if (!Number.isFinite(lat) || !Number.isFinite(lng)) {
    return { valid: false, reason: 'not_numeric', message: '地址坐标异常，请重新选点' };
  }
  if (lat === 0 && lng === 0) {
    return { valid: false, reason: 'zero_pair', message: '地址坐标无效，请重新选点' };
  }
  if (lat < -90 || lat > 90 || lng < -180 || lng > 180) {
    return { valid: false, reason: 'out_of_range', message: '地址坐标超出合法范围，请重新选点' };
  }

  return {
    valid: true,
    reason: '',
    message: '',
    lat,
    lng,
    coordinateType: TAKEOUT_COORDINATE_TYPE,
  };
}

export function buildStoredDetail(input = {}) {
  const poiName = cleanText(input.poiName || input.poi_name, 80);
  const mapAddress = cleanText(input.mapAddress || input.address, 160);
  const detail = cleanText(input.detail, 80);
  const deliveryNote = cleanText(input.deliveryNote || input.delivery_note, 120);
  const placeLine = [poiName, mapAddress].filter(Boolean).join(' · ');
  const lines = [];
  if (placeLine) lines.push(placeLine);
  if (detail) lines.push(`门牌：${detail}`);
  if (deliveryNote) lines.push(`配送说明：${deliveryNote}`);
  return lines.join('\n');
}

export function parseStoredDetail(value) {
  const raw = cleanText(value, 400);
  if (!raw) return { poiName: '', mapAddress: '', detail: '', deliveryNote: '' };

  const lines = raw.split(/\r?\n/).map((line) => line.trim()).filter(Boolean);
  const placeLine = lines.find((line) => !/^门牌[:：]|^配送说明[:：]/.test(line)) || '';
  const placeParts = placeLine.split(/\s*·\s*/);
  const poiName = cleanText(placeParts.shift(), 80);
  const mapAddress = cleanText(placeParts.join(' · '), 160);
  const detailLine = lines.find((line) => /^门牌[:：]/.test(line));
  const noteLine = lines.find((line) => /^配送说明[:：]/.test(line));

  // 旧地址没有结构化行时保留原文为地图位置，不冒充门牌信息。
  return {
    poiName,
    mapAddress,
    detail: detailLine ? cleanText(detailLine.replace(/^门牌[:：]\s*/, ''), 80) : '',
    deliveryNote: noteLine ? cleanText(noteLine.replace(/^配送说明[:：]\s*/, ''), 120) : '',
  };
}

export function normalizeTakeoutAddress(row = {}) {
  const parsed = parseStoredDetail(row.detail_address || row.detail || '');
  const poiName = cleanText(row.poi_name || row.poiName || parsed.poiName, 80);
  const mapAddress = cleanText(row.address || row.full_address || parsed.mapAddress, 160);
  const detail = cleanText(row.detail || row.doorplate || parsed.detail, 80);
  const deliveryNote = cleanText(row.delivery_note || row.deliveryNote || parsed.deliveryNote, 120);
  const region = [row.province, row.city, row.district].map((part) => cleanText(part, 40)).filter(Boolean).join('');
  const coordinate = validateGcj02Coordinates(row);

  return {
    ...row,
    poi_name: poiName,
    address: mapAddress || region,
    detail,
    delivery_note: deliveryNote,
    coordinate_type: TAKEOUT_COORDINATE_TYPE,
    lat: coordinate.valid ? coordinate.lat : row.lat,
    lng: coordinate.valid ? coordinate.lng : row.lng,
    coordinateValidation: coordinate,
  };
}

export function buildTakeoutPreviewAddressPayload({ addressId, openid, address } = {}) {
  const id = Number(addressId);
  if (!Number.isFinite(id) || id <= 0) return null;
  const userOpenid = cleanText(openid, 128);
  if (!userOpenid) return null;
  const coordinate = validateGcj02Coordinates(address || {});
  if (!coordinate.valid) return null;
  return {
    address_id: id,
    openid: userOpenid,
    lat: coordinate.lat,
    lng: coordinate.lng,
    coordinate_type: TAKEOUT_COORDINATE_TYPE,
  };
}

export function getAddressQualityWarnings(input = {}) {
  const poiName = cleanText(input.poiName || input.poi_name, 80);
  const mapAddress = cleanText(input.mapAddress || input.address, 160);
  const detail = cleanText(input.detail, 80);
  const warnings = [];
  const broadPoi = /(省|市|区|县|镇|乡|街道|工业园|产业园|开发区)$/;
  const roadOnly = /(路|街|大道|公路|国道|省道|县道)$/;
  const waterLike = /(水库|水道|湖面|河道|江面|海面|水域|湿地)$/;

  if (!poiName || broadPoi.test(poiName) || roadOnly.test(poiName)) {
    warnings.push('当前选点名称较宽泛，请把定位针移动到骑手可到达的入口');
  }
  if (!mapAddress || roadOnly.test(mapAddress)) {
    warnings.push('当前可能只选中了道路，请确认具体建筑或入口');
  }
  if (waterLike.test(poiName) || waterLike.test(mapAddress)) {
    warnings.push('当前选点名称疑似位于水域，请将定位针移到骑手可通行的入口');
  }
  if (!detail) {
    warnings.push('请补充楼栋、楼层或门牌号');
  }
  const distanceFromCurrentKm = Number(input.distanceFromCurrentKm);
  if (Number.isFinite(distanceFromCurrentKm) && distanceFromCurrentKm > 20) {
    warnings.push(`当前位置距离选点约 ${distanceFromCurrentKm.toFixed(1)} km，请确认没有选错城市或区域`);
  }
  return warnings;
}

export function buildLocationDiagnostic(input = {}) {
  const coordinate = validateGcj02Coordinates(input);
  return {
    source: cleanText(input.source || 'chooseLocation', 32),
    coordinate_type: TAKEOUT_COORDINATE_TYPE,
    accuracy: Number.isFinite(Number(input.accuracy)) ? Number(input.accuracy) : null,
    lat: coordinate.valid ? coordinate.lat : null,
    lng: coordinate.valid ? coordinate.lng : null,
  };
}
