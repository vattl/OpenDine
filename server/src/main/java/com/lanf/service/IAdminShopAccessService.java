package com.lanf.service;

import com.lanf.constant.AdminDataScope;
import com.lanf.entity.Shop;

import java.util.List;
import java.util.Map;
import java.util.Set;

/**
 * 连锁下管理员可访问门店范围（总部 / 门店绑定），见 docs/admin_chain_permission_architecture.md。
 */
public interface IAdminShopAccessService {

    /** 是否明确绑定了 {@code super_admin} 角色。 */
    boolean isSuperAdmin(Integer adminId);

    /** 是否总部视角；当前仅明确绑定 {@code super_admin} 的管理员具备总部范围。 */
    boolean isHeadquartersAdmin(Integer adminId);

    AdminDataScope resolveScope(Integer adminId);

    /**
     * 当前管理员可操作的营业中门店列表（含 id、code、name），供登录与 /admin/me/permissions 使用。
     */
    List<Shop> listAccessibleShops(Integer adminId);

    /**
     * 将门店列表转为 JSON 友好结构 [{id, code, name}]。
     */
    List<Map<String, Object>> toShopSummaries(List<Shop> shops);

    /**
     * 当前管理员可操作门店 id 集合（仅营业中门店）。
     */
    Set<Integer> listAccessibleShopIds(Integer adminId);

    /**
     * 当前管理员可访问区域 id 列表（P3）。
     */
    List<Integer> listAccessibleRegionIds(Integer adminId);
}
