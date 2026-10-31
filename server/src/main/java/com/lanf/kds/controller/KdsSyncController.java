package com.lanf.kds.controller;

import com.lanf.entity.R;
import com.lanf.kds.entity.KdsDevice;
import com.lanf.kds.service.KdsSyncService;
import com.lanf.kds.util.KdsDeviceAuth;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.web.bind.annotation.*;

import javax.servlet.http.HttpServletRequest;
import java.util.List;
import java.util.Map;

@RestController
@RequestMapping("/kds/sync")
public class KdsSyncController {

    @Autowired
    private KdsDeviceAuth deviceAuth;
    @Autowired
    private KdsSyncService syncService;
    @Autowired
    private HttpServletRequest request;

    @PostMapping("/all")
    public R syncAll(@RequestBody Map<String, Object> body) {
        try {
            KdsDevice device = deviceAuth.requireDevice(request);
            @SuppressWarnings("unchecked")
            List<Map<String, Object>> items = body.get("items") instanceof List
                    ? (List<Map<String, Object>>) body.get("items") : null;
            Map<String, Object> result = syncService.syncAll(
                    device.getShop_id(), device.getScreen_tag(), device.getStation_id(), items);
            return R.ok(result);
        } catch (IllegalStateException e) {
            return R.error(401, e.getMessage());
        }
    }

    @GetMapping("/changes")
    public R changes(@RequestParam long since) {
        try {
            KdsDevice device = deviceAuth.requireDevice(request);
            return R.ok().put("changes", syncService.changesSince(
                    device.getShop_id(), device.getScreen_tag(), since));
        } catch (IllegalStateException e) {
            return R.error(401, e.getMessage());
        }
    }
}
