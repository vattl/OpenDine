/** 从完整地址字符串尽力解析省 / 市 / 区（含直辖市） */
export function splitRegionFromChineseAddress(str) {
  const s = String(str || '').trim();
  if (!s) return { province: '', city: '', district: '', detail: '' };
  const mu = ['北京市', '天津市', '上海市', '重庆市'];
  for (const p of mu) {
    if (s.startsWith(p)) {
      const tail = s.slice(p.length);
      const dm = tail.match(/^(.+?(?:区|县))/);
      const district = dm ? dm[1] : '';
      const detail = dm ? tail.slice(dm[1].length).trim() : tail.trim();
      return { province: p, city: p, district, detail };
    }
  }
  const m = s.match(/^(.+?(?:省|自治区))(.+?(?:市|州|盟|地区))(.+?(?:区|县|市|旗))([\s\S]*)$/);
  if (m) {
    return {
      province: m[1],
      city: m[2],
      district: m[3],
      detail: (m[4] || '').trim(),
    };
  }
  return { province: '', city: '', district: '', detail: s };
}

/** 将地图 / 搜索候选的字段合并为表单可用的省市区与详细地址 */
export function buildDetailFromPlaceParts({ name, address, detail }) {
  const n = String(name || '').trim();
  const addr = String(address || '').trim();
  const part = splitRegionFromChineseAddress(addr || [n, addr].filter(Boolean).join(' '));
  let detailOut = String(detail || part.detail || '').trim();
  if (!detailOut && n && addr) {
    detailOut = addr.indexOf(n) >= 0 ? addr : `${n} ${addr}`;
  } else if (!detailOut) {
    detailOut = n || addr;
  } else if (n && detailOut.indexOf(n) < 0) {
    detailOut = `${n} ${detailOut}`.trim();
  }
  return {
    province: part.province,
    city: part.city,
    district: part.district,
    detail_address: detailOut.slice(0, 200),
  };
}
