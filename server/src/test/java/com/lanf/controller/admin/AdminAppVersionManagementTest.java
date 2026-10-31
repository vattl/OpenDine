package com.lanf.controller.admin;

import com.lanf.entity.AdminAppVersion;
import com.lanf.entity.R;
import com.lanf.interceptor.SysInterceptor;
import com.lanf.mapper.AdminAppVersionMapper;
import com.lanf.service.IAdminPermissionService;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.mock.web.MockHttpServletRequest;
import org.springframework.mock.web.MockMultipartFile;
import org.springframework.test.util.ReflectionTestUtils;

import java.nio.charset.StandardCharsets;
import java.util.*;

import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.ArgumentMatchers.*;
import static org.mockito.Mockito.*;

class AdminAppVersionManagementTest {

    private AdminAppVersionController controller;
    private AdminAppVersionMapper versionMapper;
    private IAdminPermissionService permissionService;
    private MockHttpServletRequest request;

    @BeforeEach
    void setUp() {
        controller = new AdminAppVersionController();
        versionMapper = mock(AdminAppVersionMapper.class);
        permissionService = mock(IAdminPermissionService.class);
        request = new MockHttpServletRequest();

        ReflectionTestUtils.setField(controller, "versionMapper", versionMapper);
        ReflectionTestUtils.setField(controller, "adminPermissionService", permissionService);
        ReflectionTestUtils.setField(controller, "httpServletRequest", request);
    }

    @Test
    void listVersions_whenNoSuperAdminPermission_returns403() {
        request.setAttribute(SysInterceptor.ATTR_ADMIN_ID, 100);
        when(permissionService.getPermissionCodesByAdminId(100)).thenReturn(Collections.singleton("cashier:operate"));

        R res = controller.listVersions();
        assertEquals(403, res.get("code"));
        assertTrue(res.get("msg").toString().contains("admin:super"));
        verify(versionMapper, never()).selectList(any());
    }

    @Test
    void listVersions_whenHasSuperAdminPermission_returnsData() {
        request.setAttribute(SysInterceptor.ATTR_ADMIN_ID, 1);
        when(permissionService.getPermissionCodesByAdminId(1)).thenReturn(new HashSet<>(Arrays.asList("admin:super", "cashier:operate")));

        AdminAppVersion v1 = new AdminAppVersion();
        v1.setId(1L);
        v1.setPlatform("windows");
        v1.setChannel("pos");
        v1.setLatest("2.1.0");

        when(versionMapper.selectList(any())).thenReturn(Collections.singletonList(v1));

        R res = controller.listVersions();
        assertEquals(0, res.get("code"));
        assertNotNull(res.get("data"));
        List<?> data = (List<?>) res.get("data");
        assertEquals(1, data.size());
    }

    @Test
    void saveVersion_whenNoSuperAdminPermission_returns403() {
        request.setAttribute(SysInterceptor.ATTR_ADMIN_ID, 100);
        when(permissionService.getPermissionCodesByAdminId(100)).thenReturn(Collections.emptySet());

        AdminAppVersion v = new AdminAppVersion();
        v.setPlatform("windows");
        v.setLatest("2.2.0");

        R res = controller.saveVersion(v);
        assertEquals(403, res.get("code"));
        verify(versionMapper, never()).insert(any());
        verify(versionMapper, never()).updateById(any());
    }

    @Test
    void saveVersion_withInvalidSemVer_returns400() {
        request.setAttribute(SysInterceptor.ATTR_ADMIN_ID, 1);
        when(permissionService.getPermissionCodesByAdminId(1)).thenReturn(Collections.singleton("admin:super"));

        AdminAppVersion v = new AdminAppVersion();
        v.setPlatform("windows");
        v.setChannel("pos");
        v.setLatest("not-a-valid-version");

        R res = controller.saveVersion(v);
        assertEquals(400, res.get("code"));
        assertTrue(res.get("msg").toString().contains("语义化版本号"));
    }

    @Test
    void saveVersion_withValidParameters_insertsOrUpdates() {
        request.setAttribute(SysInterceptor.ATTR_ADMIN_ID, 1);
        when(permissionService.getPermissionCodesByAdminId(1)).thenReturn(Collections.singleton("admin:super"));

        AdminAppVersion v = new AdminAppVersion();
        v.setPlatform("windows");
        v.setChannel("pos");
        v.setLatest("2.2.0");
        v.setVersion_code(20200);
        v.setMin_supported("2.0.0");
        v.setForce_update(1);
        v.setPackage_type("full");
        v.setInstall_mode("silent");

        when(versionMapper.selectOne(any())).thenReturn(null);

        R res = controller.saveVersion(v);
        assertEquals(0, res.get("code"));
        verify(versionMapper, times(1)).insert(any(AdminAppVersion.class));
    }

    @Test
    void toggleEnabled_and_deleteVersion_enforceSuperAdmin() {
        request.setAttribute(SysInterceptor.ATTR_ADMIN_ID, 100);
        when(permissionService.getPermissionCodesByAdminId(100)).thenReturn(Collections.emptySet());

        assertEquals(403, controller.toggleEnabled(1L, 0).get("code"));
        assertEquals(403, controller.deleteVersion(1L).get("code"));

        // Now grant admin:super
        when(permissionService.getPermissionCodesByAdminId(100)).thenReturn(Collections.singleton("admin:super"));
        AdminAppVersion existing = new AdminAppVersion();
        existing.setId(1L);
        existing.setEnabled(1);
        when(versionMapper.selectById(1L)).thenReturn(existing);

        R toggleRes = controller.toggleEnabled(1L, 0);
        assertEquals(0, toggleRes.get("code"));
        assertEquals(0, existing.getEnabled());
        verify(versionMapper, times(1)).updateById(existing);

        R delRes = controller.deleteVersion(1L);
        assertEquals(0, delRes.get("code"));
        verify(versionMapper, times(1)).deleteById(1L);
    }

    @Test
    void uploadPackage_whenNoSuperAdminPermission_returns403() {
        request.setAttribute(SysInterceptor.ATTR_ADMIN_ID, 100);
        when(permissionService.getPermissionCodesByAdminId(100)).thenReturn(Collections.emptySet());

        MockMultipartFile file = new MockMultipartFile("file", "app.apk", "application/vnd.android.package-archive", "dummy".getBytes(StandardCharsets.UTF_8));
        R res = controller.uploadPackage(file, "android", "pos", "1.0.0");
        assertEquals(403, res.get("code"));
        assertTrue(res.get("msg").toString().contains("admin:super"));
    }

    @Test
    void uploadPackage_whenFileEmpty_returns400() {
        request.setAttribute(SysInterceptor.ATTR_ADMIN_ID, 1);
        when(permissionService.getPermissionCodesByAdminId(1)).thenReturn(Collections.singleton("admin:super"));

        MockMultipartFile emptyFile = new MockMultipartFile("file", "app.apk", "application/vnd.android.package-archive", new byte[0]);
        R res = controller.uploadPackage(emptyFile, "android", "pos", "1.0.0");
        assertEquals(400, res.get("code"));
        assertTrue(res.get("msg").toString().contains("请选择要上传的安装包文件"));
    }

    @Test
    void uploadPackage_whenDisallowedSuffix_returns400() {
        request.setAttribute(SysInterceptor.ATTR_ADMIN_ID, 1);
        when(permissionService.getPermissionCodesByAdminId(1)).thenReturn(Collections.singleton("admin:super"));

        MockMultipartFile scriptFile = new MockMultipartFile("file", "hack.jsp", "text/plain", "malicious".getBytes(StandardCharsets.UTF_8));
        R res = controller.uploadPackage(scriptFile, "windows", "pos", "1.0.0");
        assertEquals(400, res.get("code"));
        assertTrue(res.get("msg").toString().contains("不支持的文件格式"));
    }

    @Test
    void uploadPackage_whenValidFile_computesSha256AndReturnsMetadata() {
        request.setAttribute(SysInterceptor.ATTR_ADMIN_ID, 1);
        when(permissionService.getPermissionCodesByAdminId(1)).thenReturn(Collections.singleton("admin:super"));
        ReflectionTestUtils.setField(controller, "publicBaseUrl", "https://laofei.com.cn");
        ReflectionTestUtils.setField(controller, "appPackagesFilePath", "target/test-packages/");

        byte[] payload = "Hello-Package-Installer-Binary-Test".getBytes(StandardCharsets.UTF_8);
        MockMultipartFile file = new MockMultipartFile("file", "Cashier-Setup-2.1.0.exe", "application/octet-stream", payload);

        R res = controller.uploadPackage(file, "windows", "pos", "2.1.0");
        assertEquals(0, res.get("code"));
        assertNotNull(res.get("data"));

        @SuppressWarnings("unchecked")
        Map<String, Object> data = (Map<String, Object>) res.get("data");
        assertEquals("Cashier-Setup-2.1.0.exe", data.get("fileName"));
        assertEquals((long) payload.length, data.get("fileSize"));
        assertEquals("exe", data.get("packageType"));
        assertEquals("windows", data.get("platform"));

        String downloadUrl = (String) data.get("downloadUrl");
        assertNotNull(downloadUrl);
        assertTrue(downloadUrl.startsWith("https://laofei.com.cn/admin/app/packages/windows/"));
        assertTrue(downloadUrl.endsWith(".exe"));

        String sha256 = (String) data.get("sha256");
        assertNotNull(sha256);
        assertEquals(64, sha256.length()); // SHA-256 is 64 hex characters
    }

    @Test
    void verifyUrl_requiresSuperAdmin() {
        request.setAttribute(SysInterceptor.ATTR_ADMIN_ID, 2);
        when(permissionService.getPermissionCodesByAdminId(2)).thenReturn(Collections.emptySet());

        Map<String, Object> body = new HashMap<>();
        body.put("downloadUrl", "https://laofei.com.cn/test.exe");
        R res = controller.verifyUrl(body);
        assertEquals(403, res.get("code"));
    }

    @Test
    void verifyUrl_validatesParams() {
        request.setAttribute(SysInterceptor.ATTR_ADMIN_ID, 1);
        when(permissionService.getPermissionCodesByAdminId(1)).thenReturn(Collections.singleton("admin:super"));

        R res = controller.verifyUrl(Collections.emptyMap());
        assertEquals(400, res.get("code"));
    }
}
