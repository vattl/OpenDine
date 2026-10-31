package com.lanf.dto;

import lombok.Data;

/**
 * 全局统一响应 DTO
 * 规范：code=0 成功，非0 失败；不同错误类型对应不同 code 值
 */
@Data
public class R<T> {
    // 错误码：0=成功，非0=失败（可扩展多错误码）
    private Integer code;
    // 响应消息（成功/失败描述）
    private String msg;
    // 响应数据（成功时返回，失败时可为 null）
    private T data;

    // 1. 必须保留无参构造器（Jackson 序列化/反序列化必备）
    public R() {}

    // 2. 全参构造器（自定义响应时使用）
    public R(Integer code, String msg, T data) {
        this.code = code;
        this.msg = msg;
        this.data = data;
    }

    // ====================== 成功响应重载（灵活适配不同场景）======================
    // 场景1：仅返回成功，无数据、无自定义消息（如删除操作）
    public static <T> R<T> success() {
        return new R<>(0, "操作成功", null);
    }

    // 场景2：返回成功+数据，默认消息（如查询列表/详情）
    public static <T> R<T> success(T data) {
        return new R<>(0, "操作成功", data);
    }

    // 场景3：返回成功+数据+自定义消息（如领取优惠券成功）
    public static <T> R<T> success(T data, String msg) {
        return new R<>(0, msg, data);
    }

    // 场景4：返回成功+自定义消息，无数据（如注销成功）
    public static <T> R<T> successMsg(String msg) {
        return new R<>(0, msg, null);
    }

    // ====================== 失败响应重载（支持多错误码）======================
    // 场景1：默认错误（code=1）+ 自定义消息（如业务异常）
    public static <T> R<T> fail(String msg) {
        return new R<>(1, msg, null);
    }

    // 场景2：自定义错误码+消息（如参数错误=2、权限不足=3、系统异常=500）
    public static <T> R<T> fail(Integer code, String msg) {
        return new R<>(code, msg, null);
    }

    // 场景3：自定义错误码+消息+错误数据（如参数校验失败，返回错误字段详情）
    public static <T> R<T> fail(Integer code, String msg, T data) {
        return new R<>(code, msg, data);
    }

    // ====================== 常用错误码快捷方法（简化开发）======================
    // 快捷返回：参数错误（code=2）
    public static <T> R<T> paramError(String msg) {
        return new R<>(2, msg, null);
    }

    // 快捷返回：权限不足（code=3）
    public static <T> R<T> noAuth(String msg) {
        return new R<>(3, msg, null);
    }

    // 快捷返回：资源不存在（code=4，如优惠券不存在、订单不存在）
    public static <T> R<T> notFound(String msg) {
        return new R<>(4, msg, null);
    }

    // 快捷返回：系统异常（code=500）
    public static <T> R<T> systemError(String msg) {
        return new R<>(500, msg, null);
    }
}