package com.lanf.kds.service;

import com.lanf.kds.entity.KdsDevice;
import com.lanf.kds.event.KdsDeviceCredentialChangedEvent;
import com.lanf.kds.mapper.KdsDeviceMapper;
import org.mockito.ArgumentCaptor;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.test.util.ReflectionTestUtils;
import org.springframework.context.ApplicationEventPublisher;

import java.util.Arrays;
import java.util.Collections;
import java.util.Date;
import java.util.HashSet;
import java.util.List;
import java.util.Set;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertNull;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyLong;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.times;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

/**
 * D026：KdsDeviceService 可见岗相关能力（saveScreenSelection / screenTagsOf / enrichScreens / bind 透传）。
 */
class KdsDeviceServiceTest {

    private KdsDeviceService service;
    private KdsDeviceMapper deviceMapper;
    private KdsDeviceScreenStore screenStore;
    private KdsWorkflowStore workflowStore;
    private ApplicationEventPublisher eventPublisher;

    @BeforeEach
    void setUp() {
        service = new KdsDeviceService();
        deviceMapper = mock(KdsDeviceMapper.class);
        screenStore = mock(KdsDeviceScreenStore.class);
        workflowStore = mock(KdsWorkflowStore.class);
        eventPublisher = mock(ApplicationEventPublisher.class);
        ReflectionTestUtils.setField(service, "deviceMapper", deviceMapper);
        ReflectionTestUtils.setField(service, "screenStore", screenStore);
        ReflectionTestUtils.setField(service, "workflowStore", workflowStore);
        ReflectionTestUtils.setField(service, "stationService", mock(KdsStationService.class));
        ReflectionTestUtils.setField(service, "configService", mock(KdsConfigService.class));
        ReflectionTestUtils.setField(service, "eventPublisher", eventPublisher);
    }

    private static final Set<String> THREE_GRILL = new HashSet<>(Arrays.asList(
            "meat_grill", "veg_grill", "seafood_special"));

    @Test
    @DisplayName("saveScreenSelection：合法配置写入，空/全非法删除记录")
    void saveScreenSelectionStoresOrDeletes() {
        service.saveScreenSelection(3L, Arrays.asList("meat_grill", "veg_grill"));
        verify(screenStore).save(3L, Arrays.asList("meat_grill", "veg_grill"));

        service.saveScreenSelection(4L, Arrays.asList("expedition"));
        verify(screenStore).delete(4L);
    }

    @Test
    @DisplayName("saveScreenSelection：deviceId 为 null 时不落库")
    void saveScreenSelectionNullDeviceIdNoOp() {
        service.saveScreenSelection(null, Arrays.asList("meat_grill"));
        verify(screenStore, never()).save(anyLong(), any());
        verify(screenStore, never()).delete(anyLong());
    }

    @Test
    @DisplayName("screenTagsOf：无配置默认三岗，有配置用配置")
    void screenTagsOfDefaultsToThreeGrill() {
        KdsDevice plain = new KdsDevice();
        plain.setId(1L);
        when(screenStore.get(1L)).thenReturn(Collections.emptyList());
        assertEquals(THREE_GRILL, service.screenTagsOf(plain));

        when(screenStore.get(1L)).thenReturn(Collections.singletonList("meat_grill"));
        assertEquals(Collections.singleton("meat_grill"), service.screenTagsOf(plain));

        // null 设备与无 id 设备均回默认三岗（不查 store）
        assertEquals(THREE_GRILL, service.screenTagsOf(null));
        assertEquals(THREE_GRILL, service.screenTagsOf(new KdsDevice()));
    }

    @Test
    @DisplayName("enrichScreens：回显可见岗，未配置空列表")
    void enrichScreensPopulatesField() {
        KdsDevice device = new KdsDevice();
        device.setId(8L);
        when(screenStore.get(8L)).thenReturn(Arrays.asList("meat_grill", "seafood_special"));
        KdsDevice out = service.enrichScreens(device);
        assertEquals(Arrays.asList("meat_grill", "seafood_special"), out.getScreen_tags());
    }

    @Test
    @DisplayName("bind 透传 screenTags：绑定成功后保存可见岗并回显")
    void bindPersistsScreenTags() {
        KdsDevice saved = new KdsDevice();
        saved.setId(10L);
        saved.setShop_id(5);
        saved.setDevice_code("DEV-1");
        saved.setScreen_tag("workflow_board");
        saved.setEnabled(1);
        when(deviceMapper.selectOne(any())).thenReturn(null);
        when(deviceMapper.insert(any())).thenAnswer(inv -> {
            KdsDevice d = inv.getArgument(0);
            d.setId(10L);
            return 1;
        });
        when(deviceMapper.selectById(any())).thenReturn(saved);
        when(screenStore.get(10L)).thenReturn(Collections.singletonList("meat_grill"));

        List<String> screenTags = Collections.singletonList("meat_grill");
        KdsDevice device = service.bind(5, "DEV-1", "屏1", "workflow_board", screenTags);

        assertEquals("meat_grill", device.getScreen_tags().get(0));
        verify(screenStore).save(10L, screenTags);
    }

    @Test
    @DisplayName("unbind 真正物理删除设备并清理关联数据与可见岗记录")
    void unbindCleansScreenStore() {
        KdsDevice device = new KdsDevice();
        device.setId(6L);
        device.setShop_id(5);
        device.setDevice_code("DEV-2");
        when(deviceMapper.selectOne(any())).thenReturn(device);
        service.unbind(5, "DEV-2");
        verify(screenStore).delete(6L);
        verify(workflowStore).delete(6L);
        verify(deviceMapper).deleteById(6L);
        verify(eventPublisher).publishEvent(any(KdsDeviceCredentialChangedEvent.class));
    }

    @Test
    @DisplayName("deleteDeviceById：物理删除设备并清理配对票据与关联表")
    void deleteDeviceByIdDeletesAll() {
        KdsDevice device = new KdsDevice();
        device.setId(8L);
        device.setShop_id(5);
        device.setDevice_code("DEV-8");
        when(deviceMapper.selectOne(any())).thenReturn(device);

        org.springframework.jdbc.core.JdbcTemplate jdbc = mock(org.springframework.jdbc.core.JdbcTemplate.class);
        ReflectionTestUtils.setField(service, "jdbc", jdbc);

        boolean ok = service.deleteDeviceById(5, 8L);
        assertTrue(ok);
        verify(screenStore).delete(8L);
        verify(workflowStore).delete(8L);
        verify(jdbc).update(eq("DELETE FROM t_kds_device_pairing_ticket WHERE shop_id = ? AND device_code = ?"), eq(5), eq("DEV-8"));
        verify(deviceMapper).deleteById(8L);
        verify(eventPublisher).publishEvent(any(KdsDeviceCredentialChangedEvent.class));
    }

    @Test
    @DisplayName("deleteDevice：不存在的设备返回 false 且不执行删除")
    void deleteDeviceNotFound() {
        when(deviceMapper.selectOne(any())).thenReturn(null);
        boolean ok = service.deleteDevice(5, "NOT-EXIST");
        assertFalse(ok);
        verify(deviceMapper, never()).deleteById(anyLong());
    }

    @Test
    @DisplayName("screenTagsOf 无 id 设备不查 store 且为三岗")
    void screenTagsOfNoIdIsThreeGrill() {
        assertTrue(service.screenTagsOf(new KdsDevice()).contains("meat_grill"));
    }

    @Test
    @DisplayName("saveWorkflowSelection：保存流程并持久化至 device 的 workflows_json")
    void saveWorkflowSelectionPersistsWorkflowsJson() {
        KdsDevice dev = new KdsDevice();
        dev.setId(12L);
        when(deviceMapper.selectById(12L)).thenReturn(dev);

        service.saveWorkflowSelection(12L, Arrays.asList("cook", "serve"));

        verify(workflowStore).save(12L, Arrays.asList("cook", "serve"));
        assertEquals("cook,serve", dev.getWorkflows_json());
        verify(deviceMapper).updateById(dev);
    }

    @Test
    @DisplayName("findByToken：只按 SHA-256 查找，不把原始 Token 交给数据库")
    void findByTokenUsesHashOnly() {
        KdsDevice active = new KdsDevice();
        active.setId(20L);
        active.setShop_id(5);
        active.setEnabled(1);
        active.setToken_expires_at(new Date(System.currentTimeMillis() + 60_000));
        when(deviceMapper.selectOne(any())).thenReturn(active);

        assertEquals(active, service.findByToken("cloud-secret"));

        String expectedHash = KdsDeviceService.hashToken("cloud-secret");
        ArgumentCaptor<com.baomidou.mybatisplus.core.conditions.Wrapper<KdsDevice>> queryCaptor =
                ArgumentCaptor.forClass(com.baomidou.mybatisplus.core.conditions.Wrapper.class);
        verify(deviceMapper).selectOne(queryCaptor.capture());
        com.baomidou.mybatisplus.core.conditions.query.QueryWrapper<?> query =
                (com.baomidou.mybatisplus.core.conditions.query.QueryWrapper<?>) queryCaptor.getValue();
        assertTrue(query.getSqlSegment().contains("token_hash"));
        assertTrue(query.getParamNameValuePairs().containsValue(expectedHash));
        assertFalse(query.getParamNameValuePairs().containsValue("cloud-secret"));
    }

    @Test
    @DisplayName("findByToken：过期或已撤销凭据一律失效")
    void findByTokenRejectsExpiredAndRevokedCredentials() {
        KdsDevice expired = new KdsDevice();
        expired.setEnabled(1);
        expired.setToken_expires_at(new Date(System.currentTimeMillis() - 1));
        when(deviceMapper.selectOne(any())).thenReturn(expired);
        assertNull(service.findByToken("expired"));

        KdsDevice revoked = new KdsDevice();
        revoked.setEnabled(1);
        revoked.setToken_expires_at(new Date(System.currentTimeMillis() + 60_000));
        revoked.setToken_revoked_at(new Date());
        when(deviceMapper.selectOne(any())).thenReturn(revoked);
        assertNull(service.findByToken("revoked"));
    }

    @Test
    @DisplayName("bind：签发原始 Token 只用于响应，持久化对象仅保存哈希")
    void bindPersistsHashWithoutPlaintextToken() {
        final String[] persistedHash = new String[1];
        final String[] persistedPlaintext = new String[1];
        when(deviceMapper.selectOne(any())).thenReturn(null);
        when(deviceMapper.insert(any())).thenAnswer(inv -> {
            KdsDevice candidate = inv.getArgument(0);
            candidate.setId(30L);
            persistedHash[0] = candidate.getToken_hash();
            persistedPlaintext[0] = candidate.getDevice_token();
            return 1;
        });
        KdsDevice stored = new KdsDevice();
        stored.setId(30L);
        stored.setShop_id(5);
        stored.setDevice_code("SECURE-KDS");
        stored.setScreen_tag("workflow_board");
        stored.setEnabled(1);
        when(deviceMapper.selectById(30L)).thenReturn(stored);

        KdsDevice response = service.bind(5, "SECURE-KDS", "安全屏", "workflow_board", Collections.emptyList());

        assertNull(persistedPlaintext[0]);
        assertTrue(persistedHash[0] != null && persistedHash[0].length() == 64);
        assertTrue(response.getDevice_token() != null && !response.getDevice_token().isEmpty());
        assertEquals(persistedHash[0], KdsDeviceService.hashToken(response.getDevice_token()));
        assertFalse(response.getToken_expires_at().before(new Date()));
        verify(eventPublisher).publishEvent(any(KdsDeviceCredentialChangedEvent.class));
    }

    @Test
    @DisplayName("loginBoundDevice：禁用设备在签发事务内保持拒绝且不被重新启用")
    void loginBoundDeviceRejectsDisabledWithoutMutation() {
        KdsDevice disabled = new KdsDevice();
        disabled.setId(40L);
        disabled.setShop_id(5);
        disabled.setDevice_code("DISABLED-KDS");
        disabled.setEnabled(0);
        when(deviceMapper.selectOne(any())).thenReturn(disabled);

        KdsDevice response = service.loginBoundDevice(
                5, "DISABLED-KDS", "禁用屏", "workflow_board", Collections.emptyList(), null);

        assertNull(response);
        verify(deviceMapper, never()).updateById(any(KdsDevice.class));
        verify(deviceMapper, never()).insert(any(KdsDevice.class));
        verify(eventPublisher, never()).publishEvent(any(KdsDeviceCredentialChangedEvent.class));
    }

    @Test
    @DisplayName("loginBoundDevice：同店启用设备在锁定校验后签发云端 Token")
    void loginBoundDeviceIssuesTokenForEnabledSameShopDevice() {
        KdsDevice existing = new KdsDevice();
        existing.setId(41L);
        existing.setShop_id(5);
        existing.setDevice_code("BOUND-KDS");
        existing.setScreen_tag("workflow_board");
        existing.setEnabled(1);
        when(deviceMapper.selectOne(any())).thenReturn(existing, existing);
        when(deviceMapper.selectById(41L)).thenReturn(existing);

        KdsDevice response = service.loginBoundDevice(
                5, "BOUND-KDS", "已绑定屏", "workflow_board", Collections.emptyList(), null);

        assertTrue(response.getDevice_token() != null && !response.getDevice_token().isEmpty());
        assertEquals(KdsDeviceService.hashToken(response.getDevice_token()), existing.getToken_hash());
        ArgumentCaptor<com.baomidou.mybatisplus.core.conditions.Wrapper<KdsDevice>> queryCaptor =
                ArgumentCaptor.forClass(com.baomidou.mybatisplus.core.conditions.Wrapper.class);
        verify(deviceMapper, times(2)).selectOne(queryCaptor.capture());
        assertTrue(((com.baomidou.mybatisplus.core.conditions.query.QueryWrapper<?>) queryCaptor.getAllValues().get(0))
                .getSqlSegment().contains("FOR UPDATE"));
        verify(deviceMapper).update(eq(existing), any());
    }
}
