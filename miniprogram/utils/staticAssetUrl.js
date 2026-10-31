import { getBaseUrl } from "./requestUtil.js";

/**
 * 原 miniprogram/static/ 下的资源已上传到服务端，路径为「站点根 + /image/ + 原相对路径去掉 static/」。
 * 例如原 /static/tab/gouwuche.png → https://域名/image/img/tab/gouwuche.png
 *
 * 大图列表/详情请用 utils/imageUrl.js 并带 ?q=300 或 ?q=750（服务端裁图，见 openapi GET /image/{category}/{filename}）。
 * 微信小程序 image 组件使用 https 地址时，由客户端按官方策略缓存网络图片，无需额外 downloadFile。
 *
 * @param {string} relativePath 相对 static 目录的路径，如 tab/gouwuche.png、images/default-avatar.png，或以 static/ 开头
 */
export function staticUrl(relativePath) {
  let p = String(relativePath || "").trim().replace(/^\/+/, "");
  if (p.startsWith("static/")) {
    p = p.slice(7);
  }
  return `${getBaseUrl()}/image/img/${p}`;
}
