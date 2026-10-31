package com.lanf.controller;

import com.lanf.entity.Announcement;
import com.lanf.entity.R;
import com.lanf.service.IAnnouncementService;
import com.lanf.service.IShopService;
import com.lanf.util.ShopChainSupport;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

import javax.servlet.http.HttpServletRequest;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

/**
 * C 端公告（连锁：按当前门店 + 全部门店公告）。
 */
@RestController
@RequestMapping("/announcement")
public class AnnouncementController {

    private static final int DEFAULT_C_SHOP_ID = 1;

    @Autowired
    private IAnnouncementService announcementService;
    @Autowired
    private IShopService shopService;

    @GetMapping("/list")
    public R list(@RequestParam(name = "shop_id", required = false) Integer shopId,
                  @RequestParam(name = "shop_code", required = false) String shopCode,
                  HttpServletRequest request) {
        try {
            Integer resolved = ShopChainSupport.resolveShopChain(request, shopId,
                    shopCode != null ? shopCode.trim() : null,
                    shopService::requireActiveShopIdByCode);
            if (resolved == null) {
                resolved = DEFAULT_C_SHOP_ID;
            }
            List<Announcement> list = announcementService.listEnabledForShop(resolved);
            Map<String, Object> body = new HashMap<>();
            body.put("list", list);
            body.put("total", list != null ? list.size() : 0);
            return R.ok(body);
        } catch (RuntimeException e) {
            return R.error(e.getMessage());
        }
    }
}
