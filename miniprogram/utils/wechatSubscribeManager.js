/**
 * 微信订阅消息后端可控与智能决策管理器 (WechatSubscribeManager)
 *
 * 核心能力：
 * 1. 订阅决策收口服务端 (GET /api/v1/subscribe/prompt-decision)
 *    - 用户已有可用配额 (available_quota > 0) 或已永久拒绝时，need_prompt=false，实现智能静默零打扰；
 *    - 仅在配额耗尽时返回 need_prompt=true 与精确模板 ID (最多 3 个)。
 * 2. 授权结果全量回传台账 (POST /api/v1/subscribe/report)
 *    - 将 wx.requestSubscribeMessage 的授权结果 (accept/reject/ban) 实时回传服务端更新台账配额。
 * 3. 场景覆盖：
 *    - ORDER_PICKUP: 全单出餐完成取餐通知
 *    - ORDER_STATUS: 接单制作状态流转通知
 *    - COUPON_EXPIRING: 优惠券临期到期提醒
 *    - QUEUE_CALL: 排队叫号到号提醒
 * 4. 离线/旧版后端安全降级：
 *    - 若智能决策接口不可用，安全回退至 /config/subscribe-templates 保证业务流程不阻断。
 */

import { requestUtil } from "./requestUtil.js";
import { getCurrentShopId } from "./shopContext.js";

/** 核心场景编码枚举 */
export const SUBSCRIBE_SCENES = {
  ORDER_PICKUP: "ORDER_PICKUP",
  ORDER_STATUS: "ORDER_STATUS",
  COUPON_EXPIRING: "COUPON_EXPIRING",
  QUEUE_CALL: "QUEUE_CALL",
};

/**
 * 查询指定场景是否需要弹窗授权 (GET /api/v1/subscribe/prompt-decision)
 * @param {{ scene?: string, openid?: string, shopId?: number }} params
 * @returns {Promise<{ need_prompt: boolean, tmpl_ids: string[], reason?: string, scene_decisions?: any[] }>}
 */
export async function getPromptDecision(params = {}) {
  const openid = resolveOpenid(params.openid);
  if (!openid) {
    return { need_prompt: false, tmpl_ids: [], reason: "OPENID_REQUIRED" };
  }

  const scene = params.scene ? String(params.scene).trim() : "";
  const shopId = params.shopId || Number(getCurrentShopId()) || 1;

  try {
    let url = `/api/v1/subscribe/prompt-decision?openid=${encodeURIComponent(openid)}&shop_id=${encodeURIComponent(shopId)}`;
    if (scene) {
      url += `&scene=${encodeURIComponent(scene)}`;
    }
    const res = await requestUtil({
      url,
      method: "GET",
      showLoading: false,
    });

    if (res && res.code === 0 && res.data) {
      const data = res.data;
      const tmplIds = Array.isArray(data.tmpl_ids || data.template_ids)
        ? (data.tmpl_ids || data.template_ids).filter(Boolean)
        : [];
      return {
        need_prompt: !!data.need_prompt,
        tmpl_ids: tmplIds.slice(0, 3),
        reason: data.reason || "",
        scene_decisions: data.scene_decisions || [],
      };
    }
  } catch (err) {
    console.warn("[wechatSubscribeManager] getPromptDecision failed:", err);
  }

  return { need_prompt: false, tmpl_ids: [], reason: "DECISION_API_UNAVAILABLE" };
}

/**
 * 上报微信订阅授权结果 (POST /api/v1/subscribe/report)
 * @param {{ scene?: string, openid?: string, authResults: Record<string, string> }} params
 * @returns {Promise<boolean>} 是否成功回传
 */
export async function reportAuthResult(params = {}) {
  const openid = resolveOpenid(params.openid);
  const results = params.authResults || {};
  if (!openid || !Object.keys(results).length) return false;

  const scene = params.scene ? String(params.scene).trim() : "";

  try {
    const res = await requestUtil({
      url: "/api/v1/subscribe/report",
      method: "POST",
      data: {
        openid,
        scene,
        scene_code: scene,
        auth_results: results,
        results,
      },
      showLoading: false,
    });
    return res && res.code === 0;
  } catch (err) {
    console.warn("[wechatSubscribeManager] reportAuthResult failed:", err);
    return false;
  }
}

/**
 * 查询用户当前各场景的剩余订阅配额与台账 (GET /api/v1/subscribe/quota)
 * @param {string} [openid]
 * @returns {Promise<any>}
 */
export async function getUserQuotaSummary(openid) {
  const effectiveOpenid = resolveOpenid(openid);
  if (!effectiveOpenid) return null;

  try {
    const res = await requestUtil({
      url: `/api/v1/subscribe/quota?openid=${encodeURIComponent(effectiveOpenid)}`,
      method: "GET",
      showLoading: false,
    });
    if (res && res.code === 0 && res.data) {
      return res.data;
    }
  } catch (err) {
    console.warn("[wechatSubscribeManager] getUserQuotaSummary failed:", err);
  }
  return null;
}

/**
 * 一键智能决策 + 原生订阅弹窗 + 授权回传统一接入函数
 * @param {string} sceneCode 场景编码，例如 'ORDER_PICKUP' / 'ORDER_STATUS' / 'QUEUE_CALL' / 'COUPON_EXPIRING'
 * @param {{
 *   openid?: string,
 *   shopId?: number,
 *   showToast?: boolean,
 *   fallbackTemplates?: { tmplIds?: string[], subscribeTemplateId1?: string, subscribeTemplateId2?: string }
 * }} [options]
 * @returns {Promise<{ prompted: boolean, needPrompt: boolean, authResults?: Record<string, string>, reason?: string }>}
 */
export async function requestSceneSubscribe(sceneCode, options = {}) {
  const openid = resolveOpenid(options.openid);
  const showToast = options.showToast !== false;

  if (!openid) {
    return { prompted: false, needPrompt: false, reason: "OPENID_REQUIRED" };
  }

  // 1. 服务端智能决策：配额充足或永久拒收时 need_prompt=false，极致静默零打扰
  const decision = await getPromptDecision({
    scene: sceneCode,
    openid,
    shopId: options.shopId,
  });

  let tmplIds = decision.tmpl_ids || [];

  // 若智能决策成功返回且明确不需要弹窗
  if (decision.reason !== "DECISION_API_UNAVAILABLE") {
    if (!decision.need_prompt || !tmplIds.length) {
      return {
        prompted: false,
        needPrompt: false,
        reason: decision.reason || "HAS_AVAILABLE_QUOTA",
      };
    }
  } else if (options.fallbackTemplates && Array.isArray(options.fallbackTemplates.tmplIds)) {
    // 降级使用静态配置模板
    tmplIds = options.fallbackTemplates.tmplIds.slice(0, 3);
    if (!tmplIds.length) {
      return { prompted: false, needPrompt: false, reason: "NO_FALLBACK_TEMPLATES" };
    }
  } else {
    return { prompted: false, needPrompt: false, reason: "DECISION_UNAVAILABLE" };
  }

  // 2. 必须在用户点击手势同步链路内唤起微信原生订阅弹窗
  return new Promise((resolve) => {
    wx.requestSubscribeMessage({
      tmplIds,
      success: async (res) => {
        // 过滤掉 errMsg 等系统字段，仅保留 template_id -> status ('accept' | 'reject' | 'ban')
        const results = {};
        let acceptCount = 0;
        let rejectCount = 0;

        tmplIds.forEach((id) => {
          const status = res[id];
          if (status) {
            results[id] = status;
            if (status === "accept") acceptCount++;
            else rejectCount++;
          }
        });

        // 3. 授权结果实时回传后端配额台账
        await reportAuthResult({
          openid,
          scene: sceneCode,
          authResults: results,
        });

        // 友好反馈 Toast
        if (showToast) {
          if (acceptCount > 0 && rejectCount === 0) {
            wx.showToast({ title: `已允许通知`, icon: "success", duration: 1500 });
          } else if (acceptCount > 0 && rejectCount > 0) {
            wx.showToast({ title: `已允许部分通知`, icon: "none", duration: 1500 });
          }
        }

        resolve({
          prompted: true,
          needPrompt: true,
          authResults: results,
        });
      },
      fail: (err) => {
        console.warn("[wechatSubscribeManager] wx.requestSubscribeMessage fail:", err);
        resolve({
          prompted: true,
          needPrompt: true,
          error: err,
        });
      },
    });
  });
}

function resolveOpenid(supplied) {
  if (supplied && typeof supplied === "string" && supplied.trim()) {
    return supplied.trim();
  }
  try {
    const app = typeof getApp === "function" ? getApp() : null;
    if (app && app.globalData && app.globalData.openid) {
      return String(app.globalData.openid).trim();
    }
    const stored = wx.getStorageSync("openid");
    if (stored && typeof stored === "string") {
      return stored.trim();
    }
  } catch (e) {}
  return "";
}
