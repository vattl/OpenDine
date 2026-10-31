/**
 * 网络图片 URL 统一拼接、服务端裁图 q 参数与预加载
 * 契约：GET /image/{category}/{filename}?q=宽度像素（等比缩放，见 openapi /image/{category}/{filename}）
 */
import { getBaseUrl } from "./requestUtil.js";
import { staticUrl } from "./staticAssetUrl.js";

const ABSOLUTE_RE = /^https?:\/\//i;
/** 常见图片扩展名 */
const IMAGE_EXT_RE = /\.(jpe?g|png|gif|webp|bmp|svg)(\?.*)?$/i;
/** 小程序页面路径，不能当作 GET /image/... 的文件名 */
const MP_PAGE_PATH_RE =
  /^\/?(pages\/|packageOther\/)/i;

function isMiniProgramPagePath(s) {
  const t = trimPath(s);
  if (!t) return false;
  if (MP_PAGE_PATH_RE.test(t)) return true;
  if (t.includes("pages/") && !/\/image\//i.test(t)) {
    if (/pages\/[\w-]+\/[\w-]+/i.test(t)) return true;
  }
  if (t.includes("packageOther/") && !/\/image\//i.test(t)) {
    if (/packageOther\/[\w-]+\/[\w-]+/i.test(t)) return true;
  }
  return false;
}

/**
 * 是否可作为 GET /image/{category}/{filename} 的资源路径（排除页面跳转链接）
 */
export function isServeableImagePath(raw) {
  const s = trimPath(raw);
  if (!s || isMiniProgramPagePath(s)) return false;
  if (s.startsWith("/image/") || /\/image\/(dish|img|avatar|advertising)\//i.test(s)) {
    return true;
  }
  if (IMAGE_EXT_RE.test(s)) return true;
  if (ABSOLUTE_RE.test(s)) {
    if (isMiniProgramPagePath(s)) return false;
    if (/\/image\//i.test(s) || IMAGE_EXT_RE.test(s)) return true;
    return false;
  }
  // 无扩展名的相对文件名（如服务端存的 hash 图）允许，但不含路径分隔的页面段
  if (!s.includes("pages/") && !s.includes("packageOther/")) {
    return true;
  }
  return false;
}

/**
 * 活动弹窗/轮播：展示用图优先 popup_image；image_url 多为跳转链接，仅在为图片路径时采用
 */
export function pickActivityPopupImage(item) {
  if (!item || typeof item !== "object") return "";
  const popup = trimPath(item.popup_image);
  if (popup && isServeableImagePath(popup)) return popup;
  const image = trimPath(item.image);
  if (image && isServeableImagePath(image)) return image;
  const imageUrl = trimPath(item.image_url);
  if (imageUrl && isServeableImagePath(imageUrl)) return imageUrl;
  return "";
}

/** 列表/缩略图（openapi 建议） */
export const IMAGE_Q_LIST = 300;
/** 详情/大图弹窗（openapi 建议） */
export const IMAGE_Q_DETAIL = 750;
/** 服务端 q 上限（openapi maximum: 1200） */
export const IMAGE_Q_MAX = 1200;

function baseRoot() {
  return String(getBaseUrl() || "").replace(/\/$/, "");
}

function trimPath(raw) {
  return String(raw || "").trim();
}

/**
 * 为 GET /image/{category}/... 追加 q（已有 q 或非 /image/ 路径则原样返回）
 */
export function appendImageQ(url, q) {
  const u = trimPath(url);
  if (!u || q == null || q === "") return u;
  const n = Math.min(Math.max(1, Math.floor(Number(q))), IMAGE_Q_MAX);
  if (!Number.isFinite(n)) return u;
  if (!/\/image\//i.test(u)) return u;
  if (/[?&]q=\d+/i.test(u)) return u;
  const sep = u.includes("?") ? "&" : "?";
  return `${u}${sep}q=${n}`;
}

/**
 * @param {string} raw 后端或配置中的图片路径
 * @param {{ bucket?: 'dish'|'advertising'|'img'|'raw', q?: number }} [options]
 */
export function resolveImageUrl(raw, options = {}) {
  const s = trimPath(raw);
  if (!s) return "";
  if (isMiniProgramPagePath(s)) return "";
  if (ABSOLUTE_RE.test(s)) {
    return options.q != null ? appendImageQ(s, options.q) : s;
  }
  const base = baseRoot();
  if (!base) return s;
  let url = "";
  if (s.startsWith("/image/")) {
    url = base + s;
  } else {
    const p = s.replace(/^\//, "").replace(/\\/g, "/");
    const bucket = options.bucket || "raw";
    switch (bucket) {
      case "dish":
        if (/^\/?image\/dish\//i.test(p)) {
          url = `${base}/${p.replace(/^\//, "")}`;
        } else {
          url = `${base}/image/dish/${p}`;
        }
        break;
      case "advertising":
        url = `${base}/image/advertising/${p}`;
        break;
      case "img":
        url = `${base}/image/img/${p}`;
        break;
      default:
        url = s.startsWith("/") ? base + s : `${base}/${p}`;
    }
  }
  if (options.q != null) {
    url = appendImageQ(url, options.q);
  }
  return url;
}

export function dishImageUrl(raw, q = IMAGE_Q_LIST) {
  return resolveImageUrl(raw, { bucket: "dish", q });
}

export function dishImageUrlList(raw) {
  return resolveImageUrl(raw, { bucket: "dish", q: IMAGE_Q_LIST });
}

export function dishImageUrlDetail(raw) {
  return resolveImageUrl(raw, { bucket: "dish", q: IMAGE_Q_DETAIL });
}

export function advertisingImageUrl(raw, q = IMAGE_Q_LIST) {
  return resolveImageUrl(raw, { bucket: "advertising", q });
}

export function advertisingImageUrlList(raw) {
  return resolveImageUrl(raw, { bucket: "advertising", q: IMAGE_Q_LIST });
}

export function advertisingImageUrlDetail(raw) {
  return resolveImageUrl(raw, { bucket: "advertising", q: IMAGE_Q_DETAIL });
}

export function imgAssetUrl(raw, q) {
  const opts = { bucket: "img" };
  if (q != null) opts.q = q;
  return resolveImageUrl(raw, opts);
}

/** 用户头像等任意相对路径（默认列表宽度裁图） */
export function avatarImageUrl(raw, fallback, q = IMAGE_Q_LIST) {
  const s = trimPath(raw);
  if (!s) {
    const fb = fallback || staticUrl("images/default-avatar.png");
    return appendImageQ(fb, q) || fb;
  }
  if (ABSOLUTE_RE.test(s)) return appendImageQ(s, q);
  const base = baseRoot();
  const path = s.startsWith("/") ? s : `/${s}`;
  return appendImageQ(base + path, q);
}

export function dishImageUrlOrDefault(raw, variant = "list") {
  const q = variant === "detail" ? IMAGE_Q_DETAIL : IMAGE_Q_LIST;
  const u = resolveImageUrl(raw, { bucket: "dish", q });
  return u || imgAssetUrl("images/default-avatar.png", IMAGE_Q_LIST);
}

/**
 * 并发预加载图片（写入微信客户端缓存，后续 image 组件加载更快）
 * @param {string[]} urls
 * @param {{ concurrency?: number, max?: number }} [options]
 */
export function preloadImages(urls, options = {}) {
  const concurrency = Math.max(1, options.concurrency || 4);
  const max = options.max != null ? options.max : 12;
  const list = [...new Set((urls || []).map((u) => trimPath(u)).filter(Boolean))].slice(
    0,
    max
  );
  if (!list.length) return Promise.resolve();

  return new Promise((resolve) => {
    let index = 0;
    let active = 0;
    let done = 0;

    const tick = () => {
      while (active < concurrency && index < list.length) {
        const url = list[index++];
        active++;
        wx.getImageInfo({
          src: url,
          complete: () => {
            active--;
            done++;
            if (done >= list.length) resolve();
            else tick();
          },
        });
      }
      if (index >= list.length && active === 0) resolve();
    };
    tick();
  });
}

/** 从活动/广告项列表提取 URL 并预加载（默认列表宽度 q=300） */
export function activityPopupImageUrl(item, q = IMAGE_Q_LIST) {
  const raw = pickActivityPopupImage(item);
  if (!raw) return "";
  return advertisingImageUrl(raw, q);
}

export function preloadFromMediaItems(items, pickImage, q = IMAGE_Q_LIST) {
  const urls = (items || [])
    .map((item) => {
      const img =
        typeof pickImage === "function" ? pickImage(item) : pickActivityPopupImage(item);
      if (!img) return "";
      return advertisingImageUrl(img, q) || resolveImageUrl(img, { q });
    })
    .filter(Boolean);
  return preloadImages(urls);
}
