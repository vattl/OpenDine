package com.lanf.kds.controller;

import com.lanf.entity.R;
import com.lanf.kds.entity.KdsDevice;
import com.lanf.kds.service.KdsGrillBoardService;
import com.lanf.kds.util.KdsDeviceAuth;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

import javax.servlet.http.HttpServletRequest;
import java.util.Map;

@RestController
@RequestMapping("/kds/grill")
public class KdsGrillController {

    @Autowired
    private KdsDeviceAuth deviceAuth;
    @Autowired
    private KdsGrillBoardService grillBoardService;
    @Autowired
    private HttpServletRequest request;

    /**
     * 烤制屏三栏：table_queue（待做按桌）/ product_slots（菜品固定位汇总）/ cooking（制作中）。
     */
    @GetMapping("/board")
    public R board(@RequestParam(required = false) String screen_tag,
                   @RequestParam(required = false) String screenTag) {
        try {
            KdsDevice device = deviceAuth.requireDevice(request);
            String tag = screen_tag != null ? screen_tag : screenTag;
            if (tag == null) {
                tag = device.getScreen_tag();
            }
            if (!tag.equals(device.getScreen_tag())) {
                return R.error(403, "不可查询其他岗位看板");
            }
            if (!KdsGrillBoardService.isGrillScreen(tag)) {
                return R.error(403, "仅荤烤/素烤/海鲜屏支持三栏看板");
            }
            Map<String, Object> board = grillBoardService.buildBoard(device.getShop_id(), tag);
            return R.ok(board);
        } catch (IllegalStateException e) {
            return R.error(401, e.getMessage());
        } catch (Exception e) {
            return R.error(e.getMessage());
        }
    }

    /**
     * 中间固定位：按菜品名将本屏全部待做工单合并划为制作中，并返回刷新后的三栏看板。
     */
    @PostMapping("/start-cooking")
    public R startCooking(@RequestBody Map<String, Object> body) {
        try {
            KdsDevice device = deviceAuth.requireDevice(request);
            String tag = device.getScreen_tag();
            if (!KdsGrillBoardService.isGrillScreen(tag)) {
                return R.error(403, "仅荤烤/素烤/海鲜屏支持");
            }
            Object nameObj = body != null ? (body.get("dish_name") != null ? body.get("dish_name") : body.get("dishName")) : null;
            if (nameObj == null || nameObj.toString().trim().isEmpty()) {
                return R.error("dish_name 不能为空");
            }
            Map<String, Object> board = grillBoardService.startCookingByDishName(
                    device.getShop_id(), tag, nameObj.toString().trim(), device.getStation_id());
            return R.ok(board);
        } catch (IllegalStateException e) {
            return R.error(401, e.getMessage());
        } catch (Exception e) {
            return R.error(e.getMessage());
        }
    }
}
