package com.lanf.controller.admin;

import com.baomidou.mybatisplus.core.conditions.query.QueryWrapper;
import com.lanf.entity.AdminAppVersion;
import com.lanf.entity.R;
import com.lanf.interceptor.SysInterceptor;
import com.lanf.mapper.AdminAppVersionMapper;
import com.lanf.service.IAdminPermissionService;
import com.lanf.util.AdminShopRequest;
import com.lanf.audit.annotation.AuditLog;
import com.lanf.util.SemVerUtil;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.util.StringUtils;
import org.springframework.web.bind.annotation.*;
import org.springframework.web.multipart.MultipartFile;

import java.io.*;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;

import javax.servlet.http.HttpServletRequest;
import javax.servlet.http.HttpServletResponse;
import java.util.*;

/**
 * 跨平台客户端版本策略与升级控制中心。
 * 覆盖 iOS、Android、Windows 等终端，支持智能版本比对、强制/建议升级、完整性哈希与差异化安装模式。
 */
@RestController
@RequestMapping("/admin/app")
public class AdminAppVersionController {

    private static final Logger log = LoggerFactory.getLogger(AdminAppVersionController.class);

    private static final Set<String> SUPPORTED_PLATFORMS = new HashSet<>(Arrays.asList(
            "android", "ios", "windows", "desktop", "pos_sunmi", "macos", "linux", "web"
    ));

    private static final Set<String> ALLOWED_PACKAGE_EXTENSIONS = new HashSet<>(Arrays.asList(
            ".exe", ".msi", ".apk", ".zip", ".dmg", ".pkg", ".deb", ".rpm", ".appimage", ".wgt", ".bin", ".tar", ".gz"
    ));

    @Value("${appPackagesFilePath:/www/wwwroot/upload/packages/}")
    private String appPackagesFilePath;

    @Value("${app.public-base-url:}")
    private String publicBaseUrl;

    @Autowired
    private AdminAppVersionMapper versionMapper;

    @Autowired(required = false)
    private IAdminPermissionService adminPermissionService;

    @Autowired(required = false)
    private HttpServletRequest httpServletRequest;

    public R version(String platform, String channel) {
        return version(platform, channel, null, null, null, null, null, null);
    }

    @GetMapping("/version")
    public R version(
            @RequestParam String platform,
            @RequestParam(required = false) String channel,
            @RequestParam(value = "current_version", required = false) String currentVersionParam,
            @RequestParam(value = "currentVersion", required = false) String currentVersionCamel,
            @RequestParam(value = "version_code", required = false) Integer versionCodeParam,
            @RequestParam(value = "versionCode", required = false) Integer versionCodeCamel,
            @RequestParam(value = "shop_id", required = false) Integer shopIdParam,
            @RequestParam(value = "shopId", required = false) Integer shopIdCamel) {

        String normalizedPlatform = normalizePlatform(platform);
        if (normalizedPlatform == null || !SUPPORTED_PLATFORMS.contains(normalizedPlatform)) {
            return R.error(400, "platform 仅支持 android, ios, windows, desktop, pos_sunmi 等");
        }

        String rawChannel = StringUtils.hasText(channel) ? channel : defaultChannelForPlatform(normalizedPlatform);
        String normalizedChannel = normalize(rawChannel);
        if (normalizedChannel == null || !normalizedChannel.matches("[a-z][a-z0-9_-]{0,31}")) {
            return R.error(400, "channel 格式不合法");
        }

        if ("web".equals(normalizedPlatform)) {
            Map<String, Object> data = new LinkedHashMap<>();
            data.put("platform", "web");
            data.put("channel", normalizedChannel);
            data.put("latest", currentVersionParam != null ? currentVersionParam : "1.0.0");
            data.put("versionCode", versionCodeParam != null ? versionCodeParam : 100);
            data.put("minSupported", "1.0.0");
            data.put("forceUpdate", false);
            data.put("hasUpdate", false);
            data.put("upgradeType", "NONE");
            data.put("installMode", "interactive");
            data.put("packageType", "full");
            data.put("fileSize", 0);
            data.put("sha256", null);
            data.put("releaseNotes", "当前网页端已是在线最新版本，无需更新");
            data.put("downloadUrl", null);
            return R.ok().put("data", data);
        }

        Integer effectiveShopId = shopIdParam != null ? shopIdParam : shopIdCamel;
        if (effectiveShopId == null && httpServletRequest != null) {
            effectiveShopId = AdminShopRequest.getResolvedShopId(httpServletRequest);
        }

        AdminAppVersion version = null;
        try {
            // 1. 精确匹配平台与渠道
            version = versionMapper.findCurrent(normalizedPlatform, normalizedChannel);

            // 2. 尝试平台默认渠道 (windows/desktop -> pos, android/ios -> mobile)
            if (version == null) {
                String defaultChannel = defaultChannelForPlatform(normalizedPlatform);
                if (!defaultChannel.equals(normalizedChannel)) {
                    version = versionMapper.findCurrent(normalizedPlatform, defaultChannel);
                }
            }

            // 3. 跨平台别名回退 (windows <-> desktop, android <-> pos_sunmi)
            if (version == null) {
                if ("windows".equals(normalizedPlatform)) {
                    version = versionMapper.findCurrent("desktop", normalizedChannel);
                    if (version == null) version = versionMapper.findCurrent("desktop", "pos");
                } else if ("desktop".equals(normalizedPlatform)) {
                    version = versionMapper.findCurrent("windows", normalizedChannel);
                    if (version == null) version = versionMapper.findCurrent("windows", "pos");
                } else if ("android".equals(normalizedPlatform)) {
                    version = versionMapper.findCurrent("pos_sunmi", normalizedChannel);
                    if (version == null) version = versionMapper.findCurrent("pos_sunmi", "pos");
                } else if ("pos_sunmi".equals(normalizedPlatform)) {
                    version = versionMapper.findCurrent("android", normalizedChannel);
                    if (version == null) version = versionMapper.findCurrent("android", "mobile");
                }
            }

            // 4. 忽略渠道差异：查询该平台下最新启用的任意策略
            if (version == null) {
                version = versionMapper.findCurrentByPlatform(normalizedPlatform);
            }
            if (version == null && "windows".equals(normalizedPlatform)) {
                version = versionMapper.findCurrentByPlatform("desktop");
            } else if (version == null && "desktop".equals(normalizedPlatform)) {
                version = versionMapper.findCurrentByPlatform("windows");
            } else if (version == null && "android".equals(normalizedPlatform)) {
                version = versionMapper.findCurrentByPlatform("pos_sunmi");
            } else if (version == null && "pos_sunmi".equals(normalizedPlatform)) {
                version = versionMapper.findCurrentByPlatform("android");
            }
        } catch (Exception ex) {
            log.error("[AppVersion] 查询版本策略失败，数据库可能尚未初始化 t_admin_app_version 表: {}", ex.getMessage());
            return R.error(503, "版本更新服务数据库尚未初始化，请在数据库执行 docs/db_migration_app_version_cross_platform.sql");
        }

        if (version == null) {
            // 贴心排查：是否存在已配置但未开启启用的策略，给出直接指导
            try {
                Integer disabledCount = versionMapper.selectCount(
                        new QueryWrapper<AdminAppVersion>()
                                .eq("platform", normalizedPlatform)
                                .eq("enabled", 0)
                );
                if (disabledCount != null && disabledCount > 0) {
                    return R.error(404, "当前平台（" + normalizedPlatform + "）版本策略已被停用，请在管理后台开启「启用状态」后重试");
                }
            } catch (Exception ignored) {}
            return R.error(404, "当前平台尚未发布版本策略（请求平台: " + normalizedPlatform + ", 渠道: " + normalizedChannel + "）");
        }

        // 灰度门店判定：若该最新版本配置了灰度门店，且当前门店不在灰度名单内，回退到通用版本
        if (StringUtils.hasText(version.getGray_shop_ids())) {
            boolean inGray = isShopInGrayList(effectiveShopId, version.getGray_shop_ids());
            if (!inGray) {
                AdminAppVersion generalVersion = null;
                try {
                    generalVersion = versionMapper.findCurrentGeneral(normalizedPlatform, normalizedChannel);
                    if (generalVersion == null) {
                        generalVersion = versionMapper.findCurrentGeneralByPlatform(normalizedPlatform);
                    }
                } catch (Exception ex) {
                    log.warn("[AppVersion] 查询通用版本策略失败(可能尚未补充 gray_shop_ids 列): {}", ex.getMessage());
                }
                if (generalVersion != null) {
                    version = generalVersion;
                } else {
                    return buildNoUpdateResponse(normalizedPlatform, normalizedChannel, version);
                }
            }
        }

        String currentVersion = StringUtils.hasText(currentVersionParam) ? currentVersionParam.trim()
                : (StringUtils.hasText(currentVersionCamel) ? currentVersionCamel.trim() : null);
        Integer currentVersionCode = versionCodeParam != null ? versionCodeParam : versionCodeCamel;

        // 升级类型决断 (NONE / OPTIONAL / FORCE)
        boolean hasUpdate = false;
        String upgradeType = "NONE";
        boolean policyForce = Integer.valueOf(1).equals(version.getForce_update());

        if (StringUtils.hasText(currentVersion)) {
            int cmpLatest = SemVerUtil.compare(currentVersion, version.getLatest());
            if (cmpLatest < 0) {
                hasUpdate = true;
                boolean belowMin = StringUtils.hasText(version.getMin_supported())
                        && SemVerUtil.compare(currentVersion, version.getMin_supported()) < 0;
                upgradeType = (belowMin || policyForce) ? "FORCE" : "OPTIONAL";
            } else {
                hasUpdate = false;
                upgradeType = "NONE";
            }
        } else if (currentVersionCode != null && version.getVersion_code() != null && version.getVersion_code() > 0) {
            if (currentVersionCode < version.getVersion_code()) {
                hasUpdate = true;
                upgradeType = policyForce ? "FORCE" : "OPTIONAL";
            } else {
                hasUpdate = false;
                upgradeType = "NONE";
            }
        } else {
            // 旧版本客户端未传当前版本号，保持向下兼容
            hasUpdate = true;
            upgradeType = policyForce ? "FORCE" : "OPTIONAL";
        }

        String installMode = resolveInstallMode(normalizedPlatform, version.getInstall_mode());
        String packageType = StringUtils.hasText(version.getPackage_type()) ? version.getPackage_type() : "full";

        Map<String, Object> data = new LinkedHashMap<>();
        data.put("platform", normalizedPlatform);
        data.put("channel", normalizedChannel);
        data.put("latest", version.getLatest());
        data.put("versionCode", version.getVersion_code() != null ? version.getVersion_code() : 0);
        data.put("minSupported", version.getMin_supported());
        data.put("forceUpdate", policyForce);
        data.put("hasUpdate", hasUpdate);
        data.put("upgradeType", upgradeType);
        data.put("installMode", installMode);
        data.put("packageType", packageType);
        data.put("fileSize", version.getFile_size());
        data.put("sha256", version.getSha256());
        data.put("releaseNotes", version.getRelease_notes());
        data.put("downloadUrl", version.getDownload_url());

        return R.ok().put("data", data);
    }

    private static String normalizePlatform(String platform) {
        if (platform == null) return null;
        String p = platform.trim().toLowerCase(Locale.ROOT);
        if ("win".equals(p) || "win32".equals(p) || "win64".equals(p)) {
            return "windows";
        }
        if ("apple".equals(p) || "iphone".equals(p) || "ipad".equals(p)) {
            return "ios";
        }
        if ("web".equals(p) || "h5".equals(p) || "browser".equals(p)) {
            return "web";
        }
        if ("pos".equals(p) || "cashier".equals(p)) {
            return "windows";
        }
        if ("sunmi".equals(p)) {
            return "pos_sunmi";
        }
        return p;
    }

    private static String defaultChannelForPlatform(String platform) {
        if ("windows".equals(platform) || "desktop".equals(platform)) {
            return "pos";
        }
        return "mobile";
    }

    private static String resolveInstallMode(String platform, String configuredMode) {
        if (StringUtils.hasText(configuredMode)) {
            return configuredMode.trim().toLowerCase(Locale.ROOT);
        }
        if ("ios".equals(platform)) {
            return "store_redirect";
        }
        if ("windows".equals(platform) || "desktop".equals(platform) || "pos_sunmi".equals(platform)) {
            return "silent";
        }
        return "interactive";
    }

    private static boolean isShopInGrayList(Integer shopId, String grayShopIdsStr) {
        if (shopId == null || !StringUtils.hasText(grayShopIdsStr)) {
            return false;
        }
        String cleaned = grayShopIdsStr.replaceAll("[\\[\\]\"'\\s]", "");
        String[] parts = cleaned.split("[,;]");
        String target = String.valueOf(shopId);
        for (String p : parts) {
            if (target.equals(p.trim())) {
                return true;
            }
        }
        return false;
    }

    private R buildNoUpdateResponse(String platform, String channel, AdminAppVersion version) {
        Map<String, Object> data = new LinkedHashMap<>();
        data.put("platform", platform);
        data.put("channel", channel);
        data.put("latest", version.getLatest());
        data.put("versionCode", version.getVersion_code() != null ? version.getVersion_code() : 0);
        data.put("minSupported", version.getMin_supported());
        data.put("forceUpdate", false);
        data.put("hasUpdate", false);
        data.put("upgradeType", "NONE");
        data.put("installMode", resolveInstallMode(platform, version.getInstall_mode()));
        data.put("packageType", StringUtils.hasText(version.getPackage_type()) ? version.getPackage_type() : "full");
        data.put("fileSize", version.getFile_size());
        data.put("sha256", version.getSha256());
        data.put("releaseNotes", "当前已是最新版本");
        data.put("downloadUrl", null);
        return R.ok().put("data", data);
    }

    private static String normalize(String value) {
        if (value == null) return null;
        String text = value.trim().toLowerCase(Locale.ROOT);
        return text.isEmpty() ? null : text;
    }

    /**
     * 超级管理员权限严格校验 (admin:super)。
     */
    private boolean hasSuperAdminPermission() {
        Object value = httpServletRequest != null ? httpServletRequest.getAttribute(SysInterceptor.ATTR_ADMIN_ID) : null;
        if (!(value instanceof Integer) || adminPermissionService == null) {
            return false;
        }
        try {
            Set<String> permissions = adminPermissionService.getPermissionCodesByAdminId((Integer) value);
            return permissions != null && permissions.contains("admin:super");
        } catch (RuntimeException ignored) {
            return false;
        }
    }

    /**
     * 查询所有平台的应用版本策略列表 (限 admin:super)。
     */
    @GetMapping("/versions")
    public R listVersions() {
        if (!hasSuperAdminPermission()) {
            return R.error(403, "无权限：admin:super");
        }
        try {
            List<AdminAppVersion> list = versionMapper.selectList(
                    new QueryWrapper<AdminAppVersion>()
                            .orderByAsc("platform")
                            .orderByAsc("channel")
            );
            return R.ok().put("data", list);
        } catch (Exception ex) {
            log.error("[AppVersion] 获取版本策略列表失败: {}", ex.getMessage());
            return R.error(500, "获取版本列表失败: " + ex.getMessage());
        }
    }

    /**
     * 保存或更新客户端版本策略 (限 admin:super)。
     */
    @PostMapping("/version/save")
    public R saveVersion(@RequestBody AdminAppVersion entity) {
        if (!hasSuperAdminPermission()) {
            return R.error(403, "无权限：admin:super");
        }
        if (entity == null) {
            return R.error(400, "参数不能为空");
        }
        String normalizedPlatform = normalizePlatform(entity.getPlatform());
        if (normalizedPlatform == null || !SUPPORTED_PLATFORMS.contains(normalizedPlatform)) {
            return R.error(400, "platform 仅支持 android, ios, windows, desktop, pos_sunmi 等");
        }
        entity.setPlatform(normalizedPlatform);

        String rawChannel = StringUtils.hasText(entity.getChannel()) ? entity.getChannel() : defaultChannelForPlatform(normalizedPlatform);
        String normalizedChannel = normalize(rawChannel);
        if (normalizedChannel == null || !normalizedChannel.matches("[a-z][a-z0-9_-]{0,31}")) {
            return R.error(400, "channel 格式不合法");
        }
        entity.setChannel(normalizedChannel);

        if (!StringUtils.hasText(entity.getLatest()) || !SemVerUtil.isValid(entity.getLatest())) {
            return R.error(400, "latest 必须是有效的语义化版本号 (例如 2.1.0)");
        }
        if (StringUtils.hasText(entity.getMin_supported()) && !SemVerUtil.isValid(entity.getMin_supported())) {
            return R.error(400, "min_supported 必须是有效的语义化版本号 (例如 2.0.0)");
        }

        if (entity.getForce_update() == null) {
            entity.setForce_update(0);
        }
        if (!StringUtils.hasText(entity.getPackage_type())) {
            entity.setPackage_type("full");
        }
        if (!StringUtils.hasText(entity.getInstall_mode())) {
            entity.setInstall_mode(resolveInstallMode(normalizedPlatform, null));
        }
        if (entity.getEnabled() == null) {
            entity.setEnabled(1);
        }

        try {
            if (entity.getId() != null && entity.getId() > 0) {
                versionMapper.updateById(entity);
            } else {
                AdminAppVersion existing = versionMapper.selectOne(
                        new QueryWrapper<AdminAppVersion>()
                                .eq("platform", normalizedPlatform)
                                .eq("channel", normalizedChannel)
                );
                if (existing != null) {
                    entity.setId(existing.getId());
                    versionMapper.updateById(entity);
                } else {
                    versionMapper.insert(entity);
                }
            }
            return R.ok().put("msg", "保存版本策略成功").put("id", entity.getId());
        } catch (Exception ex) {
            log.error("[AppVersion] 保存版本策略失败: {}", ex.getMessage());
            return R.error(500, "保存失败: " + ex.getMessage());
        }
    }

    /**
     * 启用/停用版本策略 (限 admin:super)。
     */
    @PostMapping("/version/toggle-enabled")
    public R toggleEnabled(@RequestParam Long id, @RequestParam Integer enabled) {
        if (!hasSuperAdminPermission()) {
            return R.error(403, "无权限：admin:super");
        }
        if (id == null) {
            return R.error(400, "id 不能为空");
        }
        AdminAppVersion version = versionMapper.selectById(id);
        if (version == null) {
            return R.error(404, "版本策略不存在");
        }
        version.setEnabled(Integer.valueOf(1).equals(enabled) ? 1 : 0);
        versionMapper.updateById(version);
        return R.ok().put("msg", "版本状态更新成功");
    }

    /**
     * 删除版本策略 (限 admin:super)。
     */
    @DeleteMapping("/version/{id}")
    public R deleteVersion(@PathVariable Long id) {
        if (!hasSuperAdminPermission()) {
            return R.error(403, "无权限：admin:super");
        }
        if (id == null) {
            return R.error(400, "id 不能为空");
        }
        versionMapper.deleteById(id);
        return R.ok().put("msg", "删除版本策略成功");
    }

    /**
     * 上传客户端安装更新包 (限 admin:super)。
     * 自动落盘存储、流式计算 SHA-256 哈希、提取文件字节大小、识别包类型并生成下载直链。
     */
    @PostMapping("/version/upload")
    @AuditLog(module = "admin", action = "admin_app_version_upload", target = "#p0.originalFilename")
    public R uploadPackage(
            @RequestParam("file") MultipartFile file,
            @RequestParam(value = "platform", required = false) String platform,
            @RequestParam(value = "channel", required = false) String channel,
            @RequestParam(value = "version", required = false) String version) {

        if (!hasSuperAdminPermission()) {
            return R.error(403, "无权限：admin:super");
        }
        if (file == null || file.isEmpty()) {
            return R.error(400, "请选择要上传的安装包文件");
        }

        String originalFilename = file.getOriginalFilename();
        if (!StringUtils.hasText(originalFilename) || !originalFilename.contains(".")) {
            return R.error(400, "文件名格式错误");
        }

        String suffix = originalFilename.substring(originalFilename.lastIndexOf(".")).toLowerCase(Locale.ROOT);
        if (!ALLOWED_PACKAGE_EXTENSIONS.contains(suffix)) {
            return R.error(400, "不支持的文件格式，仅支持: " + String.join(", ", ALLOWED_PACKAGE_EXTENSIONS));
        }

        try {
            String normalizedPlatform = normalizePlatform(platform);
            String subDir = normalizedPlatform != null ? normalizedPlatform : "common";
            String basePath = StringUtils.hasText(appPackagesFilePath) ? appPackagesFilePath.trim() : "/www/wwwroot/upload/packages/";
            File baseDir = new File(basePath);
            File targetDir = new File(baseDir, subDir);
            boolean dirReady = (targetDir.exists() || targetDir.mkdirs()) && targetDir.canWrite();
            if (!dirReady) {
                baseDir = new File(System.getProperty("user.dir"), "upload/packages");
                targetDir = new File(baseDir, subDir);
                if (!targetDir.exists()) {
                    targetDir.mkdirs();
                }
            }

            String cleanBaseName = originalFilename.substring(0, originalFilename.lastIndexOf("."))
                    .replaceAll("[^a-zA-Z0-9._-]", "_");
            if (cleanBaseName.isEmpty() || cleanBaseName.matches("_+")) {
                cleanBaseName = "package";
            }
            String storedFileName = cleanBaseName + "_" + System.currentTimeMillis() + suffix;
            File targetFile = new File(targetDir, storedFileName);

            MessageDigest sha256Digest = MessageDigest.getInstance("SHA-256");
            try (InputStream in = file.getInputStream();
                 OutputStream out = new FileOutputStream(targetFile)) {
                byte[] buffer = new byte[8192];
                int bytesRead;
                while ((bytesRead = in.read(buffer)) != -1) {
                    out.write(buffer, 0, bytesRead);
                    sha256Digest.update(buffer, 0, bytesRead);
                }
            }

            byte[] sha256Bytes = sha256Digest.digest();
            StringBuilder hexString = new StringBuilder();
            for (byte b : sha256Bytes) {
                String hex = Integer.toHexString(0xff & b);
                if (hex.length() == 1) hexString.append('0');
                hexString.append(hex);
            }
            String sha256 = hexString.toString();
            long fileSize = targetFile.length();

            String packageType = deducePackageType(suffix);
            String relativePath = subDir + "/" + storedFileName;
            String downloadUrl = buildDownloadUrl(relativePath);

            Map<String, Object> data = new LinkedHashMap<>();
            data.put("fileName", originalFilename);
            data.put("storedFileName", storedFileName);
            data.put("downloadUrl", downloadUrl);
            data.put("fileSize", fileSize);
            data.put("sha256", sha256);
            data.put("packageType", packageType);
            data.put("platform", normalizedPlatform);

            return R.ok().put("data", data).put("msg", "安装包上传成功");
        } catch (Exception ex) {
            log.error("[AppVersion] 上传安装包失败: {}", ex.getMessage(), ex);
            return R.error(500, "上传安装包失败: " + ex.getMessage());
        }
    }

    private String buildDownloadUrl(String relativePath) {
        String base = StringUtils.hasText(publicBaseUrl) ? publicBaseUrl.trim() : null;
        if (base == null && httpServletRequest != null) {
            try {
                String scheme = httpServletRequest.getScheme();
                String serverName = httpServletRequest.getServerName();
                int serverPort = httpServletRequest.getServerPort();
                if ((scheme.equals("http") && serverPort == 80) || (scheme.equals("https") && serverPort == 443)) {
                    base = scheme + "://" + serverName;
                } else if (serverName != null) {
                    base = scheme + "://" + serverName + ":" + serverPort;
                }
            } catch (Exception ignored) {}
        }
        if (base != null && base.endsWith("/")) {
            base = base.substring(0, base.length() - 1);
        }
        return (base != null ? base : "") + "/admin/app/packages/" + relativePath;
    }

    /**
     * 客户端更新安装包下载兜底接口（免签放行）。
     * 适配反代仅代理 /admin/ 前缀的场景，支持断点续传（HTTP 206 Partial Content）与精确 MIME 类型。
     */
    @GetMapping("/packages/**")
    public void downloadPackage(HttpServletRequest request, HttpServletResponse response) throws IOException {
        String uri = request.getRequestURI();
        String prefix = "/admin/app/packages/";
        if (!uri.contains(prefix)) {
            prefix = "/packages/";
        }
        int idx = uri.indexOf(prefix);
        if (idx == -1) {
            response.sendError(HttpServletResponse.SC_NOT_FOUND, "Package prefix not found");
            return;
        }
        String relativePath = uri.substring(idx + prefix.length());
        servePackage(relativePath, request, response);
    }

    private void servePackage(String relativePath, HttpServletRequest request, HttpServletResponse response) throws IOException {
        if (!StringUtils.hasText(relativePath) || relativePath.contains("..") || relativePath.startsWith("/")) {
            response.sendError(HttpServletResponse.SC_BAD_REQUEST, "Invalid file path");
            return;
        }

        File targetFile = resolvePhysicalPackageFile(relativePath);
        if (targetFile == null || !targetFile.exists() || !targetFile.isFile()) {
            response.setStatus(HttpServletResponse.SC_NOT_FOUND);
            response.setContentType("application/json;charset=UTF-8");
            response.getWriter().write("{\"code\":404,\"msg\":\"安装包文件在服务端未找到: " + relativePath + "\"}");
            return;
        }

        long length = targetFile.length();
        String filename = targetFile.getName();

        response.setHeader("Accept-Ranges", "bytes");
        response.setHeader("Content-Disposition", "attachment; filename=\"" + filename + "\"");
        response.setContentType("application/octet-stream");

        String rangeHeader = request.getHeader("Range");
        if (StringUtils.hasText(rangeHeader) && rangeHeader.startsWith("bytes=")) {
            String[] parts = rangeHeader.substring(6).split("-");
            long start = 0;
            long end = length - 1;
            try {
                if (parts.length > 0 && StringUtils.hasText(parts[0])) {
                    start = Long.parseLong(parts[0].trim());
                }
                if (parts.length > 1 && StringUtils.hasText(parts[1])) {
                    end = Long.parseLong(parts[1].trim());
                }
            } catch (NumberFormatException ignored) {}

            if (start > end || start >= length) {
                response.setStatus(HttpServletResponse.SC_REQUESTED_RANGE_NOT_SATISFIABLE);
                response.setHeader("Content-Range", "bytes */" + length);
                return;
            }

            long contentLength = end - start + 1;
            response.setStatus(HttpServletResponse.SC_PARTIAL_CONTENT);
            response.setHeader("Content-Range", "bytes " + start + "-" + end + "/" + length);
            response.setHeader("Content-Length", String.valueOf(contentLength));

            try (InputStream in = new FileInputStream(targetFile);
                 OutputStream out = response.getOutputStream()) {
                if (start > 0) {
                    long skipped = in.skip(start);
                }
                byte[] buffer = new byte[16384];
                long remaining = contentLength;
                while (remaining > 0) {
                    int read = in.read(buffer, 0, (int) Math.min(buffer.length, remaining));
                    if (read == -1) break;
                    out.write(buffer, 0, read);
                    remaining -= read;
                }
                out.flush();
            }
        } else {
            response.setStatus(HttpServletResponse.SC_OK);
            response.setHeader("Content-Length", String.valueOf(length));
            try (InputStream in = new FileInputStream(targetFile);
                 OutputStream out = response.getOutputStream()) {
                byte[] buffer = new byte[16384];
                int read;
                while ((read = in.read(buffer)) != -1) {
                    out.write(buffer, 0, read);
                }
                out.flush();
            }
        }
    }

    private File resolvePhysicalPackageFile(String relativePath) {
        String cleanRel = relativePath.replace('\\', '/');
        if (StringUtils.hasText(appPackagesFilePath)) {
            File f = new File(appPackagesFilePath.trim(), cleanRel);
            if (f.exists() && f.isFile()) {
                return f;
            }
        }
        String userDir = System.getProperty("user.dir");
        if (StringUtils.hasText(userDir)) {
            File f = new File(new File(userDir, "upload/packages"), cleanRel);
            if (f.exists() && f.isFile()) {
                return f;
            }
        }
        File defaultLinux = new File("/www/wwwroot/upload/packages/", cleanRel);
        if (defaultLinux.exists() && defaultLinux.isFile()) {
            return defaultLinux;
        }
        return null;
    }

    /**
     * 校验安装包下载直链连通性与远端 SHA-256 (限 admin:super)。
     */
    @PostMapping("/version/verify-url")
    public R verifyUrl(@RequestBody Map<String, Object> params) {
        if (!hasSuperAdminPermission()) {
            return R.error(403, "无权限：admin:super");
        }
        if (params == null || !params.containsKey("downloadUrl")) {
            return R.error(400, "downloadUrl 不能为空");
        }
        String downloadUrl = (String) params.get("downloadUrl");
        if (!StringUtils.hasText(downloadUrl)) {
            return R.error(400, "downloadUrl 不能为空");
        }
        String expectedSha = params.get("expectedSha256") != null ? params.get("expectedSha256").toString().trim() : null;

        try {
            java.net.URL url = new java.net.URL(downloadUrl);
            java.net.HttpURLConnection conn = (java.net.HttpURLConnection) url.openConnection();
            conn.setConnectTimeout(8000);
            conn.setReadTimeout(30000);
            conn.setRequestMethod("GET");
            conn.setInstanceFollowRedirects(true);
            conn.setRequestProperty("User-Agent", "LaoFei-PackageVerifier/1.0");

            int statusCode = conn.getResponseCode();
            String contentType = conn.getContentType();
            long contentLength = conn.getContentLengthLong();

            boolean isHtml = contentType != null && (contentType.toLowerCase(Locale.ROOT).contains("text/html") || contentType.toLowerCase(Locale.ROOT).contains("text/plain"));

            MessageDigest md = MessageDigest.getInstance("SHA-256");
            long totalRead = 0;
            StringBuilder previewSb = new StringBuilder();
            try (InputStream in = conn.getInputStream()) {
                byte[] buffer = new byte[8192];
                int n;
                while ((n = in.read(buffer)) != -1) {
                    md.update(buffer, 0, n);
                    totalRead += n;
                    if (isHtml && previewSb.length() < 300) {
                        previewSb.append(new String(buffer, 0, Math.min(n, 300 - previewSb.length()), StandardCharsets.UTF_8));
                    }
                }
            }

            byte[] digest = md.digest();
            StringBuilder sb = new StringBuilder();
            for (byte b : digest) {
                String hex = Integer.toHexString(0xff & b);
                if (hex.length() == 1) sb.append('0');
                sb.append(hex);
            }
            String actualSha256 = sb.toString();

            boolean matched = true;
            if (StringUtils.hasText(expectedSha)) {
                String cleanExpected = expectedSha.replaceAll("(?i)^sha256:", "").replaceAll("[^a-fA-F0-9]", "").toLowerCase(Locale.ROOT);
                matched = actualSha256.equalsIgnoreCase(cleanExpected);
            }

            Map<String, Object> data = new LinkedHashMap<>();
            data.put("statusCode", statusCode);
            data.put("contentType", contentType);
            data.put("fileSize", totalRead);
            data.put("contentLengthHeader", contentLength);
            data.put("isHtmlFallback", isHtml);
            data.put("actualSha256", actualSha256);
            data.put("hashMatched", matched);

            if (isHtml) {
                data.put("warning", "下载直链返回了网页(HTML)内容而非二进制安装包，请检查反向代理是否拦截或路由错误。预览: " + (previewSb.length() > 100 ? previewSb.substring(0, 100) + "..." : previewSb.toString()));
            } else if (!matched) {
                data.put("warning", "下载文件的 SHA-256 哈希值与预期不符！");
            }

            return R.ok().put("data", data);
        } catch (Exception ex) {
            log.error("[AppVersion] 探测下载链接失败: {}", ex.getMessage());
            return R.error(500, "探测下载链接失败: " + ex.getMessage());
        }
    }

    private static String deducePackageType(String suffix) {
        if (suffix == null) return "full";
        switch (suffix) {
            case ".exe": return "exe";
            case ".msi": return "msi";
            case ".apk": return "apk";
            case ".zip": return "zip";
            case ".dmg": return "dmg";
            case ".pkg": return "pkg";
            case ".deb": return "deb";
            case ".rpm": return "rpm";
            default: return "full";
        }
    }
}
