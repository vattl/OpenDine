/**
 * 小程序性能优化阈值（参考微信官方建议）
 * 文档：https://developers.weixin.qq.com/miniprogram/dev/framework/performance/
 */

// 页面 onLoad 建议控制在 500ms 内，否则会触发性能告警
export const PAGE_LOAD_TARGET_MS = 500;

// 首屏渲染（FCP）建议 < 1.5s
export const FIRST_PAINT_TARGET_MS = 1500;

// 可交互时间（TTI）建议 < 3s
export const TTI_TARGET_MS = 3000;

// 延后任务：onReady 内延迟执行的时间，不宜超过 PAGE_LOAD_TARGET_MS，避免用户感知卡顿
export const DEFER_READY_DELAY_MS = 300;

// 图片预加载：首屏轮播/弹窗等并发上限（utils/imageUrl.preloadImages）
export const IMAGE_PRELOAD_MAX = 12;
export const IMAGE_PRELOAD_CONCURRENCY = 4;

// 服务端裁图 q（GET /image/{category}/...?q=），与 openapi 一致：列表 300、详情 750
export { IMAGE_Q_LIST, IMAGE_Q_DETAIL, IMAGE_Q_MAX } from '../utils/imageUrl.js';

// 菜品列表缓存时间（ms），0 表示不缓存；建议 3~5 分钟，首屏可先展示缓存再静默更新
export const DISH_CACHE_TTL_MS = 5 * 60 * 1000;
export const DISH_CACHE_KEY = 'dish_list_cache';
export const DISH_CACHE_TIME_KEY = 'dish_list_cache_time';

// 菜单页静默同步售罄等状态（拉 /dish/listAll），0 关闭；不宜过小（建议 ≥25s）以省流量与 setData
export const DISH_STATUS_POLL_INTERVAL_MS = 35000;

// 活动弹窗缓存：key 与有效分钟数，秒开时先读缓存再后台刷新
export const ACTIVITY_POPUP_CACHE_KEY = 'activity_popup_page_activity';
export const ACTIVITY_POPUP_CACHE_MINUTES = 30;
