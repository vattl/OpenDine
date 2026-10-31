/** 
 * 已禁用：用于 AI 点餐“点卡片跳转并定位某道菜”的菜单锚点功能。
 * 
 * 之所以保留该文件，是为了避免旧代码里的 import 导致编译/运行失败；
 * 同时将键值设为一个几乎不可能被写入的值，确保旧逻辑不会触发定位滚动。
 */
export const PENDING_MENU_DISH_KEY = '__AI_MENU_FOCUS_DISABLED__';

