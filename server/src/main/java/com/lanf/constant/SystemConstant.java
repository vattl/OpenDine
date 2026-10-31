package com.lanf.constant;

/**
 * 系统级静态变量
 */
public class SystemConstant {

    /**
     * token
     */
    public static final int JWT_ERRCODE_NULL = 4000;			//Token不存在
    public static final int JWT_ERRCODE_EXPIRE = 4001;			//Token过期
    public static final int JWT_ERRCODE_FAIL = 4002;			//验证不通过

    /** JWT lifetime. Signing keys are runtime configuration, never source constants. */
    public static final long JWT_TTL = 24*60 * 60 * 1000;									//token有效时间
}
