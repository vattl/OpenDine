package com.lanf.kds.service;

import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import com.fasterxml.jackson.databind.ObjectMapper;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;

import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

@Service
public class KdsAuthorityConfigSnapshotService {

    private final JdbcTemplate jdbc;
    private final KdsConfigService configService;
    private final ObjectMapper objectMapper;
    private final KdsCashierAuthorityService authorityService;

    public KdsAuthorityConfigSnapshotService(JdbcTemplate jdbc, KdsConfigService configService,
                                             ObjectMapper objectMapper,
                                             KdsCashierAuthorityService authorityService) {
        this.jdbc = jdbc;
        this.configService = configService;
        this.objectMapper = objectMapper;
        this.authorityService = authorityService;
    }

    @Transactional
    public Map<String, Object> snapshot(int shopId) {
        jdbc.update("INSERT IGNORE INTO t_kds_authority_config_version (shop_id,version) VALUES (?,1)", shopId);
        Map<String, Object> versionRow = jdbc.queryForMap(
                "SELECT version,cashier_device_code FROM t_kds_authority_config_version WHERE shop_id=? FOR UPDATE", shopId);
        List<Map<String, Object>> catalog = jdbc.queryForList(
                "SELECT d.id dish_id,"
                        + "COALESCE(ds.name_override,d.name) name,"
                        + "COALESCE(ds.sorting_override,d.sorting) sorting,"
                        + "COALESCE(ds.unitprice,d.unitprice) unitprice,"
                        + "COALESCE(ds.unit_override,d.unit) unit,"
                        + "COALESCE(ds.stock,d.stock) stock,"
                        + "COALESCE(ds.sold_out,d.sold_out,0) sold_out FROM t_dish d "
                        + "LEFT JOIN t_dish_shop ds ON ds.dish_id=d.id AND ds.shop_id=? "
                        + "WHERE COALESCE(ds.onsale_override,d.onsale)=1 "
                        + "ORDER BY COALESCE(ds.sorting_override,d.sorting,2147483647),d.id", shopId);
        List<Map<String, Object>> routing = jdbc.queryForList(
                "SELECT dish_id,screen_tag FROM t_kds_dish_screen WHERE shop_id=? ORDER BY dish_id,screen_tag", shopId);
        Map<String, Object> workflow = new LinkedHashMap<>();
        com.lanf.kds.entity.KdsShopConfig cfg = configService.getOrDefault(shopId);
        workflow.put("kds_mode", cfg.getKds_mode());
        workflow.put("skewer_gate", cfg.getSkewer_gate());
        workflow.put("enable_prep_workflow", cfg.getEnable_prep_workflow());
        workflow.put("serve_print_enabled", cfg.getServe_print_enabled());
        workflow.put("auto_off_order_on_kds_done", cfg.getAuto_off_order_on_kds_done());
        workflow.put("sync_legacy_rece", cfg.getSync_legacy_rece());
        Map<String, Object> sla = new LinkedHashMap<>();
        sla.put("minutes", cfg.getSla_minutes());
        sla.put("archive_hours", cfg.getArchive_hours());
        List<Integer> fixedOrder = new ArrayList<>();
        for (Map<String, Object> dish : catalog) fixedOrder.add(((Number) dish.get("dish_id")).intValue());
        Map<String, Object> authority = new LinkedHashMap<>();
        Object configuredCode = versionRow.get("cashier_device_code");
        if (configuredCode != null) authority.put("cashier_device_code", configuredCode);
        Map<String, Object> result = new LinkedHashMap<>();
        result.put("version", ((Number) versionRow.get("version")).longValue());
        result.put("shop_id", shopId);
        result.put("catalog", catalog);
        result.put("routing", routing);
        result.put("workflow", workflow);
        result.put("sla", sla);
        result.put("fixed_order", fixedOrder);
        if (!authority.isEmpty()) authority.put("enforcement", "primary_only");
        result.put("cashier_authority", authority.isEmpty() ? null : authority);
        refreshVersion(shopId, result);
        result.put("version", jdbc.queryForObject(
                "SELECT version FROM t_kds_authority_config_version WHERE shop_id=?", Long.class, shopId));
        return result;
    }

    @Transactional
    public void setAuthorityDevice(int shopId, String deviceCode) {
        authorityService.configure(shopId, deviceCode);
    }

    private void refreshVersion(int shopId, Map<String, Object> snapshot) {
        try {
            Map<String, Object> comparable = versionMaterial(snapshot);
            String encoded = objectMapper.writeValueAsString(comparable);
            byte[] digest = MessageDigest.getInstance("SHA-256").digest(encoded.getBytes(StandardCharsets.UTF_8));
            StringBuilder hex = new StringBuilder();
            for (byte b : digest) hex.append(String.format("%02x", b));
            jdbc.update("UPDATE t_kds_authority_config_version SET version=CASE WHEN snapshot_hash IS NULL THEN version "
                            + "WHEN snapshot_hash<>? THEN version+1 ELSE version END,snapshot_hash=?,updated_at=NOW() "
                            + "WHERE shop_id=? AND (snapshot_hash IS NULL OR snapshot_hash<>?)",
                    hex.toString(), hex.toString(), shopId, hex.toString());
        } catch (Exception ex) {
            throw new IllegalStateException("config snapshot version calculation failed", ex);
        }
    }

    static Map<String, Object> versionMaterial(Map<String, Object> snapshot) {
        Map<String, Object> material = new LinkedHashMap<>();
        for (String field : new String[]{"catalog", "routing", "workflow", "sla", "fixed_order", "cashier_authority"}) {
            material.put(field, snapshot.get(field));
        }
        return material;
    }
}
