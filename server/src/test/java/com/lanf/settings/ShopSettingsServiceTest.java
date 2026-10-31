package com.lanf.settings;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.lanf.common.ApiException;
import com.lanf.entity.Shop;
import com.lanf.settings.entity.HqSettings;
import com.lanf.settings.entity.ShopSettingsOverride;
import com.lanf.settings.mapper.HqSettingsMapper;
import com.lanf.settings.mapper.ShopSettingsOverrideMapper;
import com.lanf.settings.service.ShopSettingsService;
import com.lanf.service.IShopService;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.mockito.Mockito;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.dao.DataAccessException;

import java.util.Arrays;
import java.util.Collections;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertNotNull;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

/**
 * 门店设置服务单元测试：三级合并、乐观锁 409、二次确认、校验。
 */
class ShopSettingsServiceTest {

    private ShopSettingsService service;
    private HqSettingsMapper hqMapper;
    private ShopSettingsOverrideMapper overrideMapper;
    private IShopService shopService;

    @BeforeEach
    void setUp() {
        hqMapper = mock(HqSettingsMapper.class);
        overrideMapper = mock(ShopSettingsOverrideMapper.class);
        shopService = mock(IShopService.class);
        service = new ShopSettingsService();
        org.springframework.test.util.ReflectionTestUtils.setField(service, "hqSettingsMapper", hqMapper);
        org.springframework.test.util.ReflectionTestUtils.setField(service, "shopSettingsOverrideMapper", overrideMapper);
        org.springframework.test.util.ReflectionTestUtils.setField(service, "shopService", shopService);
        org.springframework.test.util.ReflectionTestUtils.setField(service, "objectMapper", new ObjectMapper());
        org.springframework.test.util.ReflectionTestUtils.setField(service, "jdbcTemplate", mock(JdbcTemplate.class));
    }

    private Shop shop() {
        Shop shop = new Shop();
        shop.setId(1);
        shop.setName("测试门店");
        shop.setAddress("某地址");
        return shop;
    }

    private HqSettings hq(int version, String payload) {
        HqSettings hq = new HqSettings();
        hq.setModule("store");
        hq.setPayload_json(payload);
        hq.setVersion(version);
        hq.setUpdated_by(9);
        return hq;
    }

    private ShopSettingsOverride overrideRow(int version, String payload) {
        ShopSettingsOverride o = new ShopSettingsOverride();
        o.setId(77L);
        o.setShop_id(1);
        o.setModule("store");
        o.setPayload_json(payload);
        o.setVersion(version);
        o.setUpdated_by(5);
        return o;
    }

    @Test
    void getStoreInheritsHqAndFillsSystemDefaults() {
        when(overrideMapper.selectList(any())).thenReturn(Collections.emptyList());
        when(hqMapper.selectById("store")).thenReturn(hq(4, "{\"businessDays\":[1,2,3]}"));
        when(shopService.getById(1)).thenReturn(shop());

        Map<String, Object> result = service.getStoreSetting(1);

        assertEquals("HEADQUARTERS", result.get("source"));
        assertEquals(4, result.get("version"));
        assertEquals(Arrays.asList(1, 2, 3), result.get("businessDays"));
        assertNotNull(result.get("businessHours"), "未覆盖节回落系统默认");
        Map<String, Object> basic = (Map<String, Object>) result.get("basic");
        assertEquals("测试门店", basic.get("name"));
    }

    @Test
    void saveCreatesOverrideWhenVersionMatchesEffective() {
        when(hqMapper.selectById("store")).thenReturn(hq(4, null));
        when(shopService.getById(1)).thenReturn(shop());
        java.util.concurrent.atomic.AtomicReference<ShopSettingsOverride> inserted = new java.util.concurrent.atomic.AtomicReference<>();
        when(overrideMapper.insert(any(ShopSettingsOverride.class))).thenAnswer(inv -> {
            inserted.set(inv.getArgument(0));
            return 1;
        });
        when(overrideMapper.selectList(any())).thenAnswer(inv -> {
            ShopSettingsOverride row = inserted.get();
            return row == null ? Collections.emptyList() : Collections.singletonList(row);
        });

        Map<String, Object> body = new LinkedHashMap<>();
        body.put("businessHours", Collections.singletonList(new LinkedHashMap<String, Object>() {{
            put("days", Arrays.asList(1, 2));
            put("open", "09:00");
            put("close", "21:00");
            put("enabled", true);
        }}));

        Map<String, Object> result = service.saveStoreOverride(1, 4, body, 7);

        assertEquals("SHOP", result.get("source"));
        assertEquals(1, result.get("version"));
        verify(overrideMapper).insert(any(ShopSettingsOverride.class));
    }

    @Test
    void saveUpdatesBasicShopInfo() {
        Shop testShop = shop();
        when(shopService.getById(1)).thenReturn(testShop);
        when(overrideMapper.selectList(any())).thenReturn(Collections.emptyList());
        when(hqMapper.selectById("store")).thenReturn(hq(1, null));

        Map<String, Object> body = new LinkedHashMap<>();
        Map<String, Object> basic = new LinkedHashMap<>();
        basic.put("name", "更新后的门店");
        basic.put("code", "1002");
        basic.put("phone", "13800000000");
        basic.put("address", "新地址");
        basic.put("remark", "新公告备注");
        basic.put("sort", 5);
        basic.put("latitude", "22.760231");
        basic.put("longitude", "112.973179");
        basic.put("offlineCollectWechatImagePath", "/image/offline-collect/shop_1_wechat.png");
        basic.put("offlineCollectAlipayImagePath", "/image/offline-collect/shop_1_alipay.png");
        body.put("basic", basic);

        Map<String, Object> result = service.saveStoreOverride(1, 1, body, 9);
        verify(shopService).updateById(testShop);
        assertEquals("更新后的门店", testShop.getName());
        assertEquals("1002", testShop.getCode());
        assertEquals("13800000000", testShop.getContact_phone());
        assertEquals("新地址", testShop.getAddress());
        assertEquals("新公告备注", testShop.getRemark());
        assertEquals(5, testShop.getSort_order());
        assertEquals(new java.math.BigDecimal("22.760231"), testShop.getLatitude());
        assertEquals(new java.math.BigDecimal("112.973179"), testShop.getLongitude());
        assertEquals("/image/offline-collect/shop_1_wechat.png", testShop.getOffline_collect_wechat_image_path());
        assertEquals("/image/offline-collect/shop_1_alipay.png", testShop.getOffline_collect_alipay_image_path());

        Map<String, Object> resultBasic = (Map<String, Object>) result.get("basic");
        assertEquals(5, resultBasic.get("sort"));
        assertEquals("新公告备注", resultBasic.get("remark"));
        assertEquals(Boolean.TRUE, resultBasic.get("wechatQrConfigured"));
        assertEquals(Boolean.TRUE, resultBasic.get("alipayQrConfigured"));
    }

    @Test
    void saveSettleTimeUpdatesBasicAndValidatesFormat() {
        Shop testShop = shop();
        when(shopService.getById(1)).thenReturn(testShop);
        when(overrideMapper.selectList(any())).thenReturn(Collections.emptyList());
        when(hqMapper.selectById("store")).thenReturn(hq(1, null));

        Map<String, Object> body = new LinkedHashMap<>();
        Map<String, Object> basic = new LinkedHashMap<>();
        basic.put("settleTime", "03:30");
        body.put("basic", basic);

        Map<String, Object> result = service.saveStoreOverride(1, 1, body, 9);
        verify(shopService).updateById(testShop);
        assertEquals("03:30", testShop.getSettle_time());
        verify(overrideMapper, never()).insert(any(ShopSettingsOverride.class));
        Map<String, Object> resultBasic = (Map<String, Object>) result.get("basic");
        assertEquals("03:30", resultBasic.get("settleTime"));

        Map<String, Object> bad = new LinkedHashMap<>();
        Map<String, Object> badBasic = new LinkedHashMap<>();
        badBasic.put("settle_time", "25:99");
        bad.put("basic", badBasic);
        ApiException ex = assertThrows(ApiException.class, () -> service.saveStoreOverride(1, 1, bad, 9));
        assertEquals(400, ex.getHttpStatus());
        assertEquals("SETTINGS_VALIDATION_FAILED", ex.getErrorCode());
    }

    @Test
    void saveRejectsStaleVersionWithLatestSummary() {
        when(overrideMapper.selectList(any()))
                .thenReturn(Collections.singletonList(overrideRow(2, "{\"businessDays\":[1]}")));
        when(hqMapper.selectById("store")).thenReturn(null);
        when(shopService.getById(1)).thenReturn(shop());

        ApiException ex = assertThrows(ApiException.class,
                () -> service.saveStoreOverride(1, 1, new LinkedHashMap<>(), 7));
        // 空补丁先被校验拦截；改用带字段的请求验证乐观锁
        Map<String, Object> body = new LinkedHashMap<>();
        body.put("businessDays", Arrays.asList(0, 1));
        ApiException conflict = assertThrows(ApiException.class,
                () -> service.saveStoreOverride(1, 1, body, 7));
        assertEquals(409, conflict.getHttpStatus());
        assertEquals("SETTINGS_VERSION_CONFLICT", conflict.getErrorCode());
        Map<String, Object> data = (Map<String, Object>) conflict.getData();
        assertEquals(2, data.get("version"));
        assertEquals("SHOP", data.get("source"));
    }

    @Test
    void saveValidatesBusinessHours() {
        when(overrideMapper.selectList(any())).thenReturn(Collections.emptyList());
        when(hqMapper.selectById("store")).thenReturn(hq(1, null));
        when(shopService.getById(1)).thenReturn(shop());

        Map<String, Object> bad = new LinkedHashMap<>();
        bad.put("businessHours", Collections.singletonList(new LinkedHashMap<String, Object>() {{
            put("days", Arrays.asList(1));
            put("open", "21:00");
            put("close", "09:00");
            put("enabled", true);
        }}));
        ApiException ex = assertThrows(ApiException.class, () -> service.saveStoreOverride(1, 1, bad, 7));
        assertEquals(400, ex.getHttpStatus());
        assertEquals("SETTINGS_VALIDATION_FAILED", ex.getErrorCode());
        verify(overrideMapper, never()).insert(any(ShopSettingsOverride.class));
    }

    @Test
    void deleteRequiresConfirm() {
        ApiException ex = assertThrows(ApiException.class,
                () -> service.deleteOverride(1, "store", 2, false, 7));
        assertEquals(400, ex.getHttpStatus());
        assertEquals("SETTINGS_CONFIRM_REQUIRED", ex.getErrorCode());
    }

    @Test
    void deleteRemovesOverrideAndFallsBackToHq() {
        when(overrideMapper.selectList(any()))
                .thenReturn(Collections.singletonList(overrideRow(2, "{\"businessDays\":[1]}")))
                .thenReturn(Collections.emptyList());
        when(hqMapper.selectById("store")).thenReturn(hq(4, "{\"businessDays\":[1,2,3,4,5]}"));
        when(shopService.getById(1)).thenReturn(shop());

        Map<String, Object> result = service.deleteOverride(1, "store", 2, true, 7);

        verify(overrideMapper).deleteById(77L);
        assertEquals("HEADQUARTERS", result.get("source"));
        assertEquals(Arrays.asList(1, 2, 3, 4, 5), result.get("businessDays"));
    }

    @Test
    void overviewMarksModulePermission() {
        when(overrideMapper.selectList(any())).thenReturn(Collections.emptyList());
        when(hqMapper.selectById(anyString())).thenReturn(null);
        when(shopService.getById(1)).thenReturn(shop());
        JdbcTemplate jdbc = mock(JdbcTemplate.class);
        org.springframework.test.util.ReflectionTestUtils.setField(service, "jdbcTemplate", jdbc);

        List<Map<String, Object>> modules = service.overview(1,
                Collections.singleton("settings:view"));

        Map<String, Object> store = modules.stream()
                .filter(m -> "store".equals(m.get("module"))).findFirst().orElse(null);
        assertNotNull(store);
        assertEquals(Boolean.TRUE, store.get("permitted"));
        Map<String, Object> printing = modules.stream()
                .filter(m -> "printing".equals(m.get("module"))).findFirst().orElse(null);
        assertEquals(Boolean.FALSE, printing.get("permitted"));
    }
}
