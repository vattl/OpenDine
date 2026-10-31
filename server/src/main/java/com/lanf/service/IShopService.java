package com.lanf.service;

import com.baomidou.mybatisplus.extension.service.IService;
import com.lanf.entity.Shop;

public interface IShopService extends IService<Shop> {

    /**
     * 按 {@code t_shop.code} 解析营业中门店 id；{@code code} 为空或空白返回 {@code null}。
     * 不存在或非营业抛出 {@link RuntimeException}（文案供接口直接返回给用户）。
     */
    Integer requireActiveShopIdByCode(String code);
}
