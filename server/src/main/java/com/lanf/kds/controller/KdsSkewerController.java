package com.lanf.kds.controller;

import com.lanf.entity.R;
import com.lanf.kds.KdsScreenTag;
import com.lanf.kds.entity.KdsDevice;
import com.lanf.kds.service.KdsSkewerAggregateService;
import com.lanf.kds.util.KdsDeviceAuth;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.web.bind.annotation.*;

import javax.servlet.http.HttpServletRequest;
import java.util.List;
import java.util.Map;

@RestController
@RequestMapping("/kds/skewer")
public class KdsSkewerController {

    @Autowired
    private KdsDeviceAuth deviceAuth;
    @Autowired
    private KdsSkewerAggregateService skewerService;
    @Autowired
    private HttpServletRequest request;

    @GetMapping("/summary")
    public R summary() {
        try {
            KdsDevice device = deviceAuth.requireDevice(request);
            if (!KdsScreenTag.SKEWER_AGGREGATE.equals(device.getScreen_tag())) {
                return R.error(403, "仅抓串汇总屏可访问（当前设备绑定: " + device.getScreen_tag()
                        + "，请用 screen_tag=skewer_aggregate 重新登录）");
            }
            return R.ok().put("items", skewerService.summary(device.getShop_id()));
        } catch (IllegalStateException e) {
            return R.error(401, e.getMessage());
        }
    }

    @PostMapping("/picked")
    public R picked(@RequestBody Map<String, Object> body) {
        try {
            KdsDevice device = deviceAuth.requireDevice(request);
            if (!KdsScreenTag.SKEWER_AGGREGATE.equals(device.getScreen_tag())) {
                return R.error(403, "仅抓串汇总屏可操作（当前设备绑定: " + device.getScreen_tag() + "）");
            }
            String dishName = body.get("dish_name") != null ? body.get("dish_name").toString() : null;
            if (dishName == null && body.get("dishName") != null) {
                dishName = body.get("dishName").toString();
            }
            @SuppressWarnings("unchecked")
            List<Integer> detailIds = body.get("detail_ids") instanceof List
                    ? (List<Integer>) body.get("detail_ids") : null;
            int n = skewerService.picked(device.getShop_id(), dishName, detailIds);
            return R.ok().put("updated", n);
        } catch (IllegalStateException e) {
            return R.error(401, e.getMessage());
        } catch (Exception e) {
            return R.error(e.getMessage());
        }
    }
}
