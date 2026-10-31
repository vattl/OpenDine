package com.lanf.constant;

/**
 * C 端小程序鉴权相关业务码（非 B 端 JWT 401）。
 */
public final class MiniProgramAuthCodes {

    /** 登录态失效：客户端应 wx.login 后带 code 重试。 */
    public static final int LOGIN_EXPIRED = 40101;

    private MiniProgramAuthCodes() {
    }
}
