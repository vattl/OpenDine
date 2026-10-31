package com.lanf.service.impl;

import com.baomidou.mybatisplus.core.conditions.query.QueryWrapper;
import com.lanf.constant.AdminDataScope;
import com.lanf.entity.AdminRole;
import com.lanf.entity.AdminRegion;
import com.lanf.entity.AdminShop;
import com.lanf.entity.Role;
import com.lanf.entity.Shop;
import com.lanf.mapper.AdminRegionMapper;
import com.lanf.mapper.AdminRoleMapper;
import com.lanf.mapper.AdminShopMapper;
import com.lanf.mapper.RoleMapper;
import com.lanf.service.IAdminShopAccessService;
import com.lanf.service.IShopService;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.jdbc.BadSqlGrammarException;
import org.springframework.stereotype.Service;

import java.util.ArrayList;
import java.util.HashMap;
import java.util.HashSet;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.stream.Collectors;

@Service
public class AdminShopAccessServiceImpl implements IAdminShopAccessService {

    private static final Logger log = LoggerFactory.getLogger(AdminShopAccessServiceImpl.class);
    private static final String ROLE_SUPER_ADMIN = "super_admin";

    @Autowired
    private AdminRoleMapper adminRoleMapper;
    @Autowired
    private RoleMapper roleMapper;
    @Autowired
    private AdminShopMapper adminShopMapper;
    @Autowired
    private AdminRegionMapper adminRegionMapper;
    @Autowired
    private IShopService shopService;

    @Override
    public boolean isSuperAdmin(Integer adminId) {
        if (adminId == null) {
            return false;
        }
        try {
            List<AdminRole> adminRoles = adminRoleMapper.selectList(
                    new QueryWrapper<AdminRole>().eq("admin_id", adminId));
            if (adminRoles == null || adminRoles.isEmpty()) {
                return false;
            }
            for (AdminRole ar : adminRoles) {
                Role r = roleMapper.selectById(ar.getRole_id());
                if (r != null && ROLE_SUPER_ADMIN.equals(r.getRole_code())) {
                    return true;
                }
            }
        } catch (RuntimeException e) {
            log.error("查询超级管理员角色失败，按无权限处理：adminId={}", adminId, e);
            return false;
        }
        return false;
    }

    @Override
    public boolean isHeadquartersAdmin(Integer adminId) {
        return isSuperAdmin(adminId);
    }

    @Override
    public AdminDataScope resolveScope(Integer adminId) {
        if (isHeadquartersAdmin(adminId)) {
            return AdminDataScope.HQ;
        }
        List<Integer> regionIds = listAccessibleRegionIds(adminId);
        if (!regionIds.isEmpty()) {
            return AdminDataScope.REGION;
        }
        return AdminDataScope.SHOP;
    }

    @Override
    public List<Shop> listAccessibleShops(Integer adminId) {
        if (adminId == null) {
            return new ArrayList<>();
        }
        if (isHeadquartersAdmin(adminId)) {
            return shopService.list(new QueryWrapper<Shop>()
                    .eq("status", 1)
                    .orderByAsc("sort_order")
                    .orderByAsc("id"));
        }
        List<Integer> regionIds = listAccessibleRegionIds(adminId);
        if (!regionIds.isEmpty()) {
            List<Shop> regionShops = shopService.list(new QueryWrapper<Shop>()
                    .in("region_id", regionIds)
                    .eq("status", 1)
                    .orderByAsc("sort_order")
                    .orderByAsc("id"));
            List<AdminShop> links = adminShopMapper.selectList(
                    new QueryWrapper<AdminShop>().eq("admin_id", adminId));
            if (links == null || links.isEmpty()) {
                return regionShops;
            }
            Set<Integer> boundShopIds = links.stream().map(AdminShop::getShop_id).collect(Collectors.toSet());
            return regionShops.stream()
                    .filter(s -> s != null && s.getId() != null && boundShopIds.contains(s.getId()))
                    .collect(Collectors.toList());
        }
        List<AdminShop> links = adminShopMapper.selectList(
                new QueryWrapper<AdminShop>().eq("admin_id", adminId));
        if (links == null || links.isEmpty()) {
            return new ArrayList<>();
        }
        List<Integer> ids = links.stream().map(AdminShop::getShop_id).collect(Collectors.toList());
        return shopService.list(new QueryWrapper<Shop>()
                .in("id", ids)
                .eq("status", 1)
                .orderByAsc("sort_order")
                .orderByAsc("id"));
    }

    @Override
    public List<Map<String, Object>> toShopSummaries(List<Shop> shops) {
        if (shops == null) {
            return new ArrayList<>();
        }
        List<Map<String, Object>> out = new ArrayList<>(shops.size());
        for (Shop s : shops) {
            Map<String, Object> m = new HashMap<>(8);
            m.put("id", s.getId());
            m.put("code", s.getCode());
            m.put("name", s.getName());
            m.put("address", s.getAddress());
            com.lanf.util.TaxBureauResolver.TaxBureauInfo taxInfo =
                    com.lanf.util.TaxBureauResolver.resolve(s.getAddress());
            m.put("taxBureauName", taxInfo.getName());
            m.put("taxBureauUrl", taxInfo.getUrl());
            out.add(m);
        }
        return out;
    }

    @Override
    public Set<Integer> listAccessibleShopIds(Integer adminId) {
        List<Shop> shops = listAccessibleShops(adminId);
        Set<Integer> ids = new HashSet<>();
        if (shops == null || shops.isEmpty()) {
            return ids;
        }
        for (Shop shop : shops) {
            if (shop != null && shop.getId() != null) {
                ids.add(shop.getId());
            }
        }
        return ids;
    }

    @Override
    public List<Integer> listAccessibleRegionIds(Integer adminId) {
        if (adminId == null) {
            return new ArrayList<>();
        }
        List<AdminRegion> links;
        try {
            links = adminRegionMapper.selectList(
                    new QueryWrapper<AdminRegion>().eq("admin_id", adminId));
        } catch (BadSqlGrammarException e) {
            if (missingAdminRegionTable(e)) {
                log.warn("t_admin_region 未创建，按无区域绑定处理。请执行 docs/db_migration_admin_region_tables_only.sql");
                return new ArrayList<>();
            }
            throw e;
        }
        if (links == null || links.isEmpty()) {
            return new ArrayList<>();
        }
        Set<Integer> regionIds = new LinkedHashSet<>();
        for (AdminRegion link : links) {
            if (link != null && link.getRegion_id() != null) {
                regionIds.add(link.getRegion_id());
            }
        }
        return new ArrayList<>(regionIds);
    }

    private static boolean missingAdminRegionTable(BadSqlGrammarException e) {
        Throwable c = e.getMostSpecificCause();
        String msg = c != null ? c.getMessage() : e.getMessage();
        if (msg == null) {
            return false;
        }
        String m = msg.toLowerCase();
        return m.contains("t_admin_region") && m.contains("doesn't exist");
    }
}
