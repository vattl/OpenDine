package com.lanf.constant;

/**
 * 运营后台数据范围（连锁），与登录响应字段 scope 字符串一致。
 */
public enum AdminDataScope {
    /** 总部：可管全部门店（或等价于未绑定门店时的超管语义） */
    HQ,
    /** 区域：按 t_admin_region 映射出的门店范围 */
    REGION,
    /** 门店：仅 t_admin_shop（及单店兼容） */
    SHOP
}
