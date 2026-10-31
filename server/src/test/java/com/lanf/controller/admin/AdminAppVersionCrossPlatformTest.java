package com.lanf.controller.admin;

import com.lanf.entity.AdminAppVersion;
import com.lanf.entity.R;
import com.lanf.mapper.AdminAppVersionMapper;
import com.lanf.util.SemVerUtil;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.mock.web.MockHttpServletRequest;
import org.springframework.test.util.ReflectionTestUtils;

import java.util.Map;

import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.*;

class AdminAppVersionCrossPlatformTest {

    private AdminAppVersionController controller;
    private AdminAppVersionMapper versionMapper;
    private MockHttpServletRequest request;

    @BeforeEach
    void setUp() {
        controller = new AdminAppVersionController();
        versionMapper = mock(AdminAppVersionMapper.class);
        request = new MockHttpServletRequest();
        ReflectionTestUtils.setField(controller, "versionMapper", versionMapper);
        ReflectionTestUtils.setField(controller, "httpServletRequest", request);
    }

    @Test
    void semVerComparison_correctlyHandlesMultiSegmentNumerics() {
        assertTrue(SemVerUtil.isLessThan("2.0.1", "2.0.10"));
        assertTrue(SemVerUtil.isGreaterThan("2.0.10", "2.0.2"));
        assertTrue(SemVerUtil.isLessThan("1.9.9", "2.0.0"));
        assertTrue(SemVerUtil.isEqual("v2.1.0+build123", "2.1.0"));
        assertTrue(SemVerUtil.isEqual("2.1.0-rc1", "2.1.0"));
        assertEquals(0, SemVerUtil.compare("2.0.0", "2.0"));
    }

    @Test
    void windowsPlatform_returnsSilentInstallMode_and_sha256Checksum() {
        AdminAppVersion winPolicy = new AdminAppVersion();
        winPolicy.setPlatform("windows");
        winPolicy.setChannel("pos");
        winPolicy.setLatest("2.1.0");
        winPolicy.setVersion_code(20100);
        winPolicy.setMin_supported("2.0.0");
        winPolicy.setForce_update(0);
        winPolicy.setInstall_mode("silent");
        winPolicy.setPackage_type("full");
        winPolicy.setFile_size(85420112L);
        winPolicy.setSha256("e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855");
        winPolicy.setDownload_url("https://download.example.com/pos-win-2.1.0.exe");
        winPolicy.setRelease_notes("Windows收银端性能优化");

        when(versionMapper.findCurrent(eq("windows"), eq("pos"))).thenReturn(winPolicy);

        // 1. 客户端当前版本低于最新版，但高于最低支持版本 -> OPTIONAL, silent
        R res = controller.version("windows", "pos", "2.0.5", null, null, null, null, null);
        assertEquals(0, res.get("code"));

        @SuppressWarnings("unchecked")
        Map<String, Object> data = (Map<String, Object>) res.get("data");
        assertNotNull(data);
        assertEquals("windows", data.get("platform"));
        assertEquals("pos", data.get("channel"));
        assertEquals("2.1.0", data.get("latest"));
        assertEquals(true, data.get("hasUpdate"));
        assertEquals("OPTIONAL", data.get("upgradeType"));
        assertEquals("silent", data.get("installMode"));
        assertEquals(85420112L, data.get("fileSize"));
        assertEquals("e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855", data.get("sha256"));
    }

    @Test
    void iosPlatform_returnsStoreRedirect_and_forceUpdateWhenBelowMinSupported() {
        AdminAppVersion iosPolicy = new AdminAppVersion();
        iosPolicy.setPlatform("ios");
        iosPolicy.setChannel("mobile");
        iosPolicy.setLatest("2.1.0");
        iosPolicy.setVersion_code(20100);
        iosPolicy.setMin_supported("2.0.5");
        iosPolicy.setForce_update(0);
        iosPolicy.setInstall_mode("store_redirect");
        iosPolicy.setDownload_url("itms-apps://itunes.apple.com/app/id123456789");
        iosPolicy.setRelease_notes("iOS版本更新");

        when(versionMapper.findCurrent(eq("ios"), eq("mobile"))).thenReturn(iosPolicy);

        // 当前版本 2.0.1 低于最低支持版本 2.0.5 -> 判定为 FORCE 强制更新
        R res = controller.version("ios", "mobile", "2.0.1", null, null, null, null, null);
        assertEquals(0, res.get("code"));

        @SuppressWarnings("unchecked")
        Map<String, Object> data = (Map<String, Object>) res.get("data");
        assertNotNull(data);
        assertEquals("store_redirect", data.get("installMode"));
        assertEquals(true, data.get("hasUpdate"));
        assertEquals("FORCE", data.get("upgradeType"));
        assertEquals("itms-apps://itunes.apple.com/app/id123456789", data.get("downloadUrl"));
    }

    @Test
    void androidPlatform_returnsNoUpdateWhenCurrentIsLatest() {
        AdminAppVersion androidPolicy = new AdminAppVersion();
        androidPolicy.setPlatform("android");
        androidPolicy.setChannel("mobile");
        androidPolicy.setLatest("2.1.0");
        androidPolicy.setVersion_code(20100);
        androidPolicy.setMin_supported("2.0.0");
        androidPolicy.setForce_update(0);
        androidPolicy.setInstall_mode("interactive");
        androidPolicy.setDownload_url("https://download.example.com/app-2.1.0.apk");

        when(versionMapper.findCurrent(eq("android"), eq("mobile"))).thenReturn(androidPolicy);

        // 当前已是最新版本 2.1.0
        R res = controller.version("android", "mobile", "2.1.0", null, null, null, null, null);
        assertEquals(0, res.get("code"));

        @SuppressWarnings("unchecked")
        Map<String, Object> data = (Map<String, Object>) res.get("data");
        assertNotNull(data);
        assertEquals(false, data.get("hasUpdate"));
        assertEquals("NONE", data.get("upgradeType"));
    }

    @Test
    void grayShopFilter_returnsGrayVersionOnlyForConfiguredShop() {
        AdminAppVersion grayPolicy = new AdminAppVersion();
        grayPolicy.setPlatform("windows");
        grayPolicy.setChannel("pos");
        grayPolicy.setLatest("2.2.0-beta");
        grayPolicy.setMin_supported("2.0.0");
        grayPolicy.setGray_shop_ids("[1, 2]");

        AdminAppVersion stablePolicy = new AdminAppVersion();
        stablePolicy.setPlatform("windows");
        stablePolicy.setChannel("pos");
        stablePolicy.setLatest("2.1.0");
        stablePolicy.setMin_supported("2.0.0");
        stablePolicy.setGray_shop_ids(null);

        when(versionMapper.findCurrent(eq("windows"), eq("pos"))).thenReturn(grayPolicy);
        when(versionMapper.findCurrentGeneral(eq("windows"), eq("pos"))).thenReturn(stablePolicy);

        // 1. 门店 1 在灰度名单中 -> 命中 2.2.0-beta
        R resShop1 = controller.version("windows", "pos", "2.0.0", null, null, null, 1, null);
        @SuppressWarnings("unchecked")
        Map<String, Object> data1 = (Map<String, Object>) resShop1.get("data");
        assertEquals("2.2.0-beta", data1.get("latest"));

        // 2. 门店 3 不在灰度名单中 -> 回退到稳定通用版本 2.1.0
        R resShop3 = controller.version("windows", "pos", "2.0.0", null, null, null, 3, null);
        @SuppressWarnings("unchecked")
        Map<String, Object> data3 = (Map<String, Object>) resShop3.get("data");
        assertEquals("2.1.0", data3.get("latest"));
    }

    @Test
    void channelMismatch_fallsBackToPlatformDefaultOrAnyEnabledPolicy() {
        AdminAppVersion androidPolicy = new AdminAppVersion();
        androidPolicy.setPlatform("android");
        androidPolicy.setChannel("pos");
        androidPolicy.setLatest("2.1.3");
        androidPolicy.setVersion_code(210);
        androidPolicy.setMin_supported("2.0.0");
        androidPolicy.setForce_update(0);
        androidPolicy.setInstall_mode("interactive");
        androidPolicy.setPackage_type("apk");

        // Client requests channel "mobile", but DB has it under "pos"
        when(versionMapper.findCurrent(eq("android"), eq("mobile"))).thenReturn(null);
        when(versionMapper.findCurrentByPlatform(eq("android"))).thenReturn(androidPolicy);

        R res = controller.version("android", "mobile", "2.1.0", null, null, null, null, null);
        assertEquals(0, res.get("code"));
        @SuppressWarnings("unchecked")
        Map<String, Object> data = (Map<String, Object>) res.get("data");
        assertEquals("2.1.3", data.get("latest"));
        assertTrue((Boolean) data.get("hasUpdate"));
    }

    @Test
    void disabledPolicy_returnsClearPromptToEnableInAdmin() {
        when(versionMapper.findCurrent(any(), any())).thenReturn(null);
        when(versionMapper.findCurrentByPlatform(any())).thenReturn(null);
        when(versionMapper.selectCount(any())).thenReturn(1);

        R res = controller.version("android", "mobile", "2.1.0", null, null, null, null, null);
        assertEquals(404, res.get("code"));
        assertTrue(res.get("msg").toString().contains("已被停用"));
    }

    @Test
    void webPlatform_returnsNoUpdateGracefully() {
        R res = controller.version("web", "pos", "2.1.0", null, null, null, null, null);
        assertEquals(0, res.get("code"));
        @SuppressWarnings("unchecked")
        Map<String, Object> data = (Map<String, Object>) res.get("data");
        assertEquals("web", data.get("platform"));
        assertFalse((Boolean) data.get("hasUpdate"));
    }
}
