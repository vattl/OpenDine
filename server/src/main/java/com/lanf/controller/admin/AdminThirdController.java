package com.lanf.controller.admin;

import com.lanf.entity.R;
import org.springframework.web.bind.annotation.*;

import java.util.*;

/**
 * 外卖对接（美团/饿了么）- 接单同步、状态回传、对账（桩实现）
 */
@RestController
@RequestMapping("/admin/third")
public class AdminThirdController {

    @PostMapping("/order/sync")
    public R sync(@RequestBody Map<String, Object> body) {
        String platform = body != null ? (String) body.get("platform") : null;
        String orderSn = body != null ? (String) body.get("order_sn") : null;
        if (platform == null || orderSn == null) {
            return R.error("platform与order_sn不能为空");
        }
        String orderNo = "T" + System.currentTimeMillis();
        return R.ok().put("order_no", orderNo);
    }

    @PostMapping("/order/statusPush")
    public R statusPush(@RequestBody Map<String, Object> body) {
        String orderNo = body != null ? (String) body.get("order_no") : null;
        String status = body != null ? (String) body.get("status") : null;
        if (orderNo == null || status == null) {
            return R.error("order_no与status不能为空");
        }
        return R.ok();
    }

    @GetMapping("/reconciliation")
    public R reconciliation(@RequestParam(required = false) String platform, @RequestParam(required = false) String date) {
        return R.ok().put("list", Collections.emptyList());
    }
}
