package com.lanf.service;

/**
 * 微信小程序 code 换 openid，并维护 t_user。
 */
public interface WechatMiniProgramAuthService {

    /**
     * 用 wx.login 的 code 换取 openid（并更新 session_key / user_type）。
     */
    String exchangeCodeForOpenid(String code);

    /**
     * 解析请求中的 openid：若提供 code 则优先用 code 换取最新 openid；
     * 否则使用已有 openid；均无时返回 null。
     */
    String resolveOpenid(String openid, String wxCode);
}
