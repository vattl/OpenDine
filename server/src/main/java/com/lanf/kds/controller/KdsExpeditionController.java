package com.lanf.kds.controller;

import com.lanf.entity.R;
import com.lanf.kds.KdsScreenTag;
import com.lanf.kds.entity.KdsDevice;
import com.lanf.kds.service.KdsExpeditionServeService;
import com.lanf.kds.service.KdsOverviewBoardService;
import com.lanf.kds.util.KdsDeviceAuth;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.util.StringUtils;
import org.springframework.web.bind.annotation.*;

import javax.servlet.http.HttpServletRequest;
import java.util.Map;

/**
 * 出餐屏：看板展示与收银总览一致；待传菜支持按菜品分批确认传菜。
 */
@RestController
@RequestMapping("/kds/expedition")
public class KdsExpeditionController {

    @Autowired
    private KdsDeviceAuth deviceAuth;
    @Autowired
    private KdsOverviewBoardService overviewBoardService;
    @Autowired
    private KdsExpeditionServeService expeditionServeService;
    @Autowired
    private HttpServletRequest request;

    @GetMapping("/board")
    public R board(@RequestParam(required = false) String queue,
                   @RequestParam(required = false) String dining,
                   @RequestParam(required = false) String view,
                   @RequestParam(required = false) String extra) {
        try {
            KdsDevice device = deviceAuth.requireDevice(request);
            if (!KdsScreenTag.EXPEDITION.equals(device.getScreen_tag())) {
                return R.error(403, "仅出餐屏可访问该看板");
            }
            Map<String, Object> board = overviewBoardService.buildBoard(
                    device.getShop_id(), queue, dining, view, extra);
            board.put("screen_tag", KdsScreenTag.EXPEDITION);
            return R.ok(board);
        } catch (IllegalStateException e) {
            return R.error(401, e.getMessage());
        } catch (Exception e) {
            return R.error(e.getMessage());
        }
    }

    /**
     * 待传菜分批出餐：按菜品完成时间 done_at 从早到晚扣减数量。
     */
    @PostMapping("/serve")
    public R serve(@RequestBody Map<String, Object> body) {
        try {
            KdsDevice device = deviceAuth.requireDevice(request);
            if (!KdsScreenTag.EXPEDITION.equals(device.getScreen_tag())) {
                return R.error(403, "仅出餐屏可操作传菜");
            }
            String dishName = text(body, "dish_name", "dishName");
            Integer qty = asInt(body.get("quantity"), body.get("qty"));
            String screenTag = text(body, "screen_tag", "screenTag");
            if (dishName == null) {
                return R.error("dish_name 不能为空");
            }
            if (qty == null || qty <= 0) {
                return R.error("quantity 必须大于 0");
            }
            Map<String, Object> result = expeditionServeService.serveByDish(
                    device.getShop_id(), dishName, qty, screenTag);
            return R.ok(result);
        } catch (IllegalStateException e) {
            return R.error(401, e.getMessage());
        } catch (Exception e) {
            return R.error(e.getMessage());
        }
    }

    private static String text(Map<String, Object> body, String... keys) {
        if (body == null) {
            return null;
        }
        for (String k : keys) {
            Object v = body.get(k);
            if (v != null && StringUtils.hasText(v.toString())) {
                return v.toString().trim();
            }
        }
        return null;
    }

    private static Integer asInt(Object a, Object b) {
        Object o = a != null ? a : b;
        if (o instanceof Number) {
            return ((Number) o).intValue();
        }
        if (o != null) {
            try {
                return Integer.parseInt(o.toString().trim());
            } catch (NumberFormatException ignore) {
                return null;
            }
        }
        return null;
    }
}
