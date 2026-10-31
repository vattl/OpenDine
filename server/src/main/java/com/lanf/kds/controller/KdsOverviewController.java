package com.lanf.kds.controller;

import com.lanf.entity.R;
import com.lanf.kds.KdsScreenTag;
import com.lanf.kds.entity.KdsDevice;
import com.lanf.kds.service.KdsOverviewBoardService;
import com.lanf.kds.util.KdsDeviceAuth;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

import javax.servlet.http.HttpServletRequest;
import java.util.Map;

/**
 * 收银总览屏：老板/收银跨岗查看待制作、待传菜、已完成。
 */
@RestController
@RequestMapping("/kds/overview")
public class KdsOverviewController {

    @Autowired
    private KdsDeviceAuth deviceAuth;
    @Autowired
    private KdsOverviewBoardService overviewBoardService;
    @Autowired
    private HttpServletRequest request;

    @GetMapping("/board")
    public R board(@RequestParam(required = false) String queue,
                   @RequestParam(required = false) String dining,
                   @RequestParam(required = false) String view,
                   @RequestParam(required = false) String extra) {
        try {
            KdsDevice device = deviceAuth.requireDevice(request);
            if (!KdsScreenTag.BOSS_OVERVIEW.equals(device.getScreen_tag())) {
                return R.error(403, "仅收银总览屏可访问该看板");
            }
            Map<String, Object> board = overviewBoardService.buildBoard(
                    device.getShop_id(), queue, dining, view, extra);
            return R.ok(board);
        } catch (IllegalStateException e) {
            return R.error(401, e.getMessage());
        } catch (Exception e) {
            return R.error(e.getMessage());
        }
    }
}
