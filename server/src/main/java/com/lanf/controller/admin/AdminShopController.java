package com.lanf.controller.admin;

import com.baomidou.mybatisplus.core.conditions.query.QueryWrapper;
import com.baomidou.mybatisplus.core.conditions.update.UpdateWrapper;
import com.lanf.entity.R;
import com.lanf.entity.Shop;
import com.lanf.constant.AdminDataScope;
import com.lanf.security.AdminShopScopeGuard;
import com.lanf.service.IAdminShopAccessService;
import com.lanf.service.IShopService;
import com.lanf.util.OfflineCollectQrCodec;
import com.lanf.util.CoordinateNormalizer;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.web.bind.annotation.*;
import org.springframework.web.multipart.MultipartFile;
import javax.servlet.http.HttpServletRequest;
import java.io.ByteArrayInputStream;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.Paths;
import java.util.List;
import java.util.Locale;

/**
 * 门店管理（收银系统扩展）
 */
@RestController
@RequestMapping("/admin/shop")
public class AdminShopController {

    @Autowired
    private IShopService shopService;
    @Autowired
    private HttpServletRequest httpServletRequest;
    @Autowired
    private AdminShopScopeGuard adminShopScopeGuard;
    @Autowired
    private IAdminShopAccessService adminShopAccessService;

    @Value("${offlineCollectImgsFilePath:/www/wwwroot/upload/offline-collect/}")
    private String offlineCollectImgsFilePath;

    /**
     * 多门店列表查询（仅用于全局门店选择器/下拉框选店/总部多店总览）。
     * 单店深度设置请使用 {@code GET /admin/settings/store}。
     */
    @GetMapping("/list")
    public R list(@RequestParam(required = false) Integer enabled,
                  @RequestParam(required = false) String keyword) {
        QueryWrapper<Shop> q = new QueryWrapper<>();
        Integer adminId = currentAdminId();
        if (adminId == null) {
            return R.error(401, "未登录或登录已过期");
        }
        try {
            if (adminShopAccessService.resolveScope(adminId) != AdminDataScope.HQ) {
                java.util.Set<Integer> allowed = adminShopAccessService.listAccessibleShopIds(adminId);
                if (allowed == null || allowed.isEmpty()) {
                    return R.ok().put("list", java.util.Collections.emptyList());
                }
                q.in("id", allowed);
            }
        } catch (RuntimeException e) {
            return R.error(4003, "管理员数据范围校验失败");
        }
        if (enabled != null) {
            q.eq("status", enabled);
        }
        if (keyword != null && !keyword.trim().isEmpty()) {
            String kw = keyword.trim();
            q.and(w -> w.like("name", kw).or().like("code", kw));
        }
        q.orderByAsc("id");
        List<Shop> list = shopService.list(q);
        return R.ok().put("list", list);
    }

    /**
     * 保存门店基本信息（历史兼容接口）。
     * @deprecated 自 v1.2.132 起废弃，请统一迁移至 {@code PUT /admin/settings/store}（支持 version 乐观锁与完整营业时段配置）。
     */
    @Deprecated
    @PostMapping("/save")
    public R save(@RequestBody Shop shop) {
        if (shop == null) {
            return R.error("参数不能为空");
        }
        if (shop.getStatus() == null) {
            shop.setStatus(1);
        }
        try {
            normalizeCoordinates(shop);
        } catch (IllegalArgumentException e) {
            return R.error(e.getMessage());
        }
        if (shop.getId() == null) {
            R scopeError = adminShopScopeGuard.requireHeadquarters();
            if (scopeError != null) {
                return scopeError;
            }
        } else {
            int[] target = new int[1];
            R scopeError = adminShopScopeGuard.resolveTargetShopId(shop.getId(), target);
            if (scopeError != null) {
                return scopeError;
            }
            if (target[0] <= 0) {
                return R.error(400, "门店 ID 必须大于 0");
            }
            shop.setId(target[0]);
        }
        shopService.saveOrUpdate(shop);
        return R.ok();
    }

    private static void normalizeCoordinates(Shop shop) {
        if (shop.getLatitude() == null && shop.getLongitude() == null) {
            return;
        }
        if (shop.getLatitude() == null || shop.getLongitude() == null) {
            throw new IllegalArgumentException("门店经度 longitude 与纬度 latitude 必须同时提供");
        }
        CoordinateNormalizer.Point point = CoordinateNormalizer.toGcj02(
                shop.getLatitude().doubleValue(), shop.getLongitude().doubleValue(), shop.getCoordinate_type());
        shop.setLatitude(CoordinateNormalizer.decimal(point.getLat()));
        shop.setLongitude(CoordinateNormalizer.decimal(point.getLng()));
        shop.setCoordinate_type(CoordinateNormalizer.GCJ02);
    }

    /**
     * 上传门店线下微信/支付宝收款码图片：解码二维码为跳转串写入库，不向前端返回原图内容。
     * 当前门店来自 {@code X-Shop-Id}；总部无门店上下文时可传 query/body {@code shopId}。
     */
    @PostMapping("/offline-collect/upload")
    public R uploadOfflineCollect(@RequestParam(required = false) MultipartFile wechatQr,
                                  @RequestParam(required = false) MultipartFile alipayQr,
                                  @RequestParam(required = false) Integer shopId) throws Exception {
        if ((wechatQr == null || wechatQr.isEmpty()) && (alipayQr == null || alipayQr.isEmpty())) {
            return R.error(400, "请至少上传 wechatQr 或 alipayQr 其一");
        }
        int[] target = new int[1];
        R scopeError = adminShopScopeGuard.resolveTargetShopId(shopId, target);
        if (scopeError != null) {
            return scopeError;
        }
        int targetShopId = target[0];
        if (targetShopId <= 0) {
            return R.error(400, "请指定具体门店");
        }
        Shop existing = shopService.getById(targetShopId);
        if (existing == null) {
            return R.error(404, "门店不存在");
        }
        UpdateWrapper<Shop> uw = new UpdateWrapper<Shop>().eq("id", targetShopId);
        Path dir = Paths.get(offlineCollectImgsFilePath);
        Files.createDirectories(dir);
        if (wechatQr != null && !wechatQr.isEmpty()) {
            byte[] raw = wechatQr.getBytes();
            String decoded;
            try {
                decoded = OfflineCollectQrCodec.decodeFirstQrPayload(new ByteArrayInputStream(raw));
            } catch (Exception ex) {
                return R.error(400, "微信收款码识别失败：" + ex.getMessage());
            }
            if (!OfflineCollectQrCodec.looksLikeWechatCollectPayload(decoded)) {
                return R.error(400, "微信收款码解码结果不像有效收款链接，请确认上传的是微信个人收款码截图");
            }
            String ext = fileExt(wechatQr.getOriginalFilename());
            String fn = "shop_" + targetShopId + "_wechat." + ext;
            Path dest = dir.resolve(fn);
            Files.write(dest, raw);
            uw.set("offline_collect_wechat_payload", decoded.trim());
            uw.set("offline_collect_wechat_image_path", "/image/offline-collect/" + fn);
        }
        if (alipayQr != null && !alipayQr.isEmpty()) {
            byte[] raw = alipayQr.getBytes();
            String decoded;
            try {
                decoded = OfflineCollectQrCodec.decodeFirstQrPayload(new ByteArrayInputStream(raw));
            } catch (Exception ex) {
                return R.error(400, "支付宝收款码识别失败：" + ex.getMessage());
            }
            if (!OfflineCollectQrCodec.looksLikeAlipayCollectPayload(decoded)) {
                return R.error(400, "支付宝收款码解码结果不像有效收款链接，请确认上传的是支付宝收款码截图");
            }
            String ext = fileExt(alipayQr.getOriginalFilename());
            String fn = "shop_" + targetShopId + "_alipay." + ext;
            Path dest = dir.resolve(fn);
            Files.write(dest, raw);
            uw.set("offline_collect_alipay_payload", decoded.trim());
            uw.set("offline_collect_alipay_image_path", "/image/offline-collect/" + fn);
        }
        shopService.update(uw);
        return R.ok("上传并解析成功");
    }

    private Integer currentAdminId() {
        Object value = httpServletRequest.getAttribute(com.lanf.interceptor.SysInterceptor.ATTR_ADMIN_ID);
        return value instanceof Integer ? (Integer) value : null;
    }

    private static String fileExt(String originalFilename) {
        if (originalFilename == null || !originalFilename.contains(".")) {
            return "png";
        }
        String e = originalFilename.substring(originalFilename.lastIndexOf('.') + 1).toLowerCase(Locale.ROOT);
        if (e.length() > 8 || !e.matches("[a-z0-9]+")) {
            return "png";
        }
        return e;
    }
}
