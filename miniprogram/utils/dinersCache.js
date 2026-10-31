/** 堂食就餐人数缓存有效期（分钟） */
export const DINERS_CACHE_EXPIRY_MINUTES = 15;

const DINERS_STORAGE_KEY = "number_of_diners";
/** 旧版独立 TTL 键，读取后迁移至 DINERS_STORAGE_KEY */
const DINERS_TTL_LEGACY_KEY = "number_of_diners_ttl";

function resolveApp(app) {
  if (app && typeof app.getStorageWithExpiry === "function") return app;
  try {
    const g = typeof getApp === "function" ? getApp() : null;
    if (g && typeof g.getStorageWithExpiry === "function") return g;
  } catch (e) {
    /* ignore */
  }
  return null;
}

/** 从 sync 原始值解析人数（兼容历史 plain number 或误写的 expiry 包装对象） */
export function normalizeDinersRaw(raw) {
  if (raw == null || raw === "") return null;
  if (typeof raw === "object") {
    const inner = raw.data != null ? raw.data : raw.value;
    if (inner != null) {
      const n = Number(inner);
      if (Number.isFinite(n) && n > 0) return Math.floor(n);
    }
    return null;
  }
  const n = Number(raw);
  if (Number.isFinite(n) && n > 0) return Math.floor(n);
  return null;
}

function readDinersFromExpiryStorage(inst, key) {
  if (!inst || typeof inst.getStorageWithExpiry !== "function") return null;
  const cached = inst.getStorageWithExpiry(key);
  const n = Number(cached);
  if (Number.isFinite(n) && n > 0) return Math.floor(n);
  return null;
}

function writeDinersWithExpiry(inst, count) {
  if (!inst || typeof inst.setStorageWithExpiry !== "function") return;
  inst.setStorageWithExpiry(
    DINERS_STORAGE_KEY,
    count,
    DINERS_CACHE_EXPIRY_MINUTES
  );
}

/**
 * 读取有效就餐人数（15 分钟内，App.setStorageWithExpiry）
 * @returns {number|null}
 */
export function getValidDinersCount(app) {
  const inst = resolveApp(app);
  if (inst) {
    const current = readDinersFromExpiryStorage(inst, DINERS_STORAGE_KEY);
    if (current != null) return current;

    const legacyTtl = readDinersFromExpiryStorage(inst, DINERS_TTL_LEGACY_KEY);
    if (legacyTtl != null) {
      writeDinersWithExpiry(inst, legacyTtl);
      try {
        wx.removeStorageSync(DINERS_TTL_LEGACY_KEY);
      } catch (e) {
        /* ignore */
      }
      return legacyTtl;
    }
  }

  try {
    const migrated = normalizeDinersRaw(wx.getStorageSync(DINERS_STORAGE_KEY));
    if (migrated != null && inst) {
      writeDinersWithExpiry(inst, migrated);
    }
    return migrated;
  } catch (e) {
    /* ignore */
  }
  return null;
}

/** 确认页/下单用：有效缓存人数，缺省 2 */
export function getDinersCountOrDefault(app, defaultCount = 2) {
  const n = getValidDinersCount(app);
  if (n != null) return n;
  const d = Number(defaultCount);
  return Number.isFinite(d) && d > 0 ? Math.floor(d) : 2;
}

/** 写入就餐人数（App.setStorageWithExpiry，15 分钟有效） */
export function saveDinersCount(app, diners) {
  const n = Number(diners);
  if (!Number.isFinite(n) || n <= 0) return;
  const count = Math.floor(n);
  const inst = resolveApp(app);
  if (!inst) return;
  try {
    writeDinersWithExpiry(inst, count);
  } catch (e) {
    /* ignore */
  }
}

/** 构建带人数、堂食、台号的点餐页 reLaunch 参数 */
export function buildHomePageDineInQuery({ diners, tableNumber }) {
  const qs = [
    `dineInOrTakeOut=${encodeURIComponent("堂食")}`,
    `number_people=${encodeURIComponent(String(diners))}`,
  ];
  const tn = tableNumber ? String(tableNumber).trim() : "";
  if (tn) qs.push(`table_number=${encodeURIComponent(tn)}`);
  return qs.join("&");
}
