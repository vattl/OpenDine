/**
 * 菜品规格（t_dish.specification JSON，如 {"辣度":["微辣","中辣"]}）
 */

export function parseDishSpecification(raw) {
  if (raw == null || raw === "") return null;
  try {
    const v = typeof raw === "string" ? JSON.parse(raw) : raw;
    if (!v || typeof v !== "object" || Array.isArray(v)) return null;
    const out = {};
    Object.keys(v).forEach((k) => {
      const opts = v[k];
      if (!Array.isArray(opts)) return;
      const list = opts.map((x) => String(x).trim()).filter(Boolean);
      if (list.length) out[k] = list;
    });
    return Object.keys(out).length ? out : null;
  } catch (e) {
    return null;
  }
}

/** 与点餐弹窗一致：有 2 项及以上默认选第二项 */
export function buildDefaultSelectedSpicy(spec) {
  const selected = {};
  if (!spec) return selected;
  Object.keys(spec).forEach((type) => {
    const options = spec[type];
    if (options.length >= 2) selected[type] = options[1];
    else if (options.length === 1) selected[type] = options[0];
    else selected[type] = "";
  });
  return selected;
}

export function validateSelectedSpicy(spec, selected) {
  if (!spec || !Object.keys(spec).length) return { ok: true };
  const picked = selected && typeof selected === "object" ? selected : {};
  for (const type of Object.keys(spec)) {
    const val = picked[type];
    if (!val || !spec[type].includes(val)) {
      return { ok: false, message: `请选择${type}` };
    }
  }
  return { ok: true };
}

export function serializeSelectedSpicy(selected) {
  if (!selected || typeof selected !== "object") return "";
  const keys = Object.keys(selected);
  if (!keys.length) return "";
  return JSON.stringify(selected);
}

/** 展示用：微辣、中辣 或 辣度:微辣 */
export function formatSelectedSpicyText(spicy) {
  if (spicy == null || spicy === "") return "";
  if (typeof spicy === "object" && spicy !== null && !Array.isArray(spicy)) {
    const parts = Object.entries(spicy)
      .map(([, value]) => String(value).trim())
      .filter(Boolean);
    return parts.join("、");
  }
  const s = String(spicy).trim();
  if (!s || s === "{}") return "";
  try {
    const parsed = JSON.parse(s);
    if (parsed && typeof parsed === "object" && !Array.isArray(parsed)) {
      return Object.entries(parsed)
        .map(([, value]) => String(value).trim())
        .filter(Boolean)
        .join("、");
    }
    return typeof parsed === "string" ? parsed : s;
  } catch (e) {
    return s;
  }
}

export function resolveComboHeaderSpecification(header, dishSnapshot) {
  const fromHeader =
    header && header.specification != null ? header.specification : "";
  const fromSnap =
    dishSnapshot && dishSnapshot.specification != null
      ? dishSnapshot.specification
      : "";
  return fromHeader || fromSnap || "";
}
