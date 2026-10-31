package com.lanf.kds.controller;

import com.lanf.entity.R;
import com.lanf.kds.KdsItemStatus;
import com.lanf.kds.KdsScreenTag;
import com.lanf.kds.entity.KdsDevice;
import com.lanf.kds.entity.KdsTicket;
import com.lanf.kds.service.KdsLackService;
import com.lanf.kds.service.KdsTicketService;
import com.lanf.kds.service.KdsWorkflowService;
import com.lanf.kds.support.KdsAdvanceRequestContext;
import com.lanf.kds.util.KdsDeviceAuth;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.web.bind.annotation.*;

import javax.servlet.http.HttpServletRequest;
import java.util.Map;

@RestController
@RequestMapping("/kds/item")
public class KdsItemController {

    @Autowired
    private KdsDeviceAuth deviceAuth;
    @Autowired
    private KdsTicketService ticketService;
    @Autowired
    private KdsLackService lackService;
    @Autowired
    private HttpServletRequest request;
    @Autowired
    private KdsWorkflowService workflowService;

    @PostMapping("/status/update")
    public R statusUpdate(@RequestBody Map<String, Object> body) {
        try {
            KdsDevice device = deviceAuth.requireDevice(request);
            Integer detailId = asInt(body.get("detail_id"), body.get("item_id"), body.get("detailId"), body.get("itemId"));
            if (detailId == null || detailId <= 0) {
                return R.error("detail_id 不能为空且必须为正整数");
            }
            String fromQueue = body.get("from_queue") != null ? body.get("from_queue").toString()
                    : (body.get("fromQueue") != null ? body.get("fromQueue").toString() : null);
            Integer quantity = asInt(body.get("quantity"), body.get("qty"));
            Long rowVersion = asLong(body.get("row_version"), body.get("rowVersion"));
            KdsAdvanceRequestContext context = new KdsAdvanceRequestContext(
                    asInt(body.get("expected_order_id"), body.get("expectedOrderId")),
                    asText(body.get("expected_table_number"), body.get("expectedTableNumber")),
                    asText(body.get("expected_dish_name"), body.get("expectedDishName")));
            Map<String, Object> result = workflowService.statusUpdateFast(
                    device.getShop_id(), detailId, fromQueue, quantity != null ? quantity : 1, rowVersion, context);
            return R.ok(result);
        } catch (KdsWorkflowService.OptimisticLockException e) {
            return R.error(5001, e.getMessage());
        } catch (IllegalStateException e) {
            return R.error(401, e.getMessage());
        } catch (IllegalArgumentException e) {
            return R.error(e.getMessage());
        } catch (Exception e) {
            return R.error(e.getMessage() != null ? e.getMessage() : "快速划菜失败");
        }
    }

    private static Long asLong(Object... candidates) {
        for (Object o : candidates) {
            if (o == null) {
                continue;
            }
            if (o instanceof Number) {
                return ((Number) o).longValue();
            }
            try {
                return Long.parseLong(o.toString().trim());
            } catch (NumberFormatException ignore) {
                // next
            }
        }
        return null;
    }

    private static String asText(Object... candidates) {
        for (Object value : candidates) {
            if (value != null && !value.toString().trim().isEmpty()) return value.toString().trim();
        }
        return null;
    }

    @PostMapping("/status")
    public R status(@RequestBody Map<String, Object> body) {
        try {
            KdsDevice device = deviceAuth.requireDevice(request);
            Integer detailId = asInt(body.get("item_id"), body.get("detail_id"), body.get("itemId"));
            Integer status = asInt(body.get("status"), body.get("item_status"));
            if (detailId == null || detailId <= 0) {
                return R.error("item_id/detail_id 不能为空且必须为正整数");
            }
            if (status == null || !KdsItemStatus.isValid(status)) {
                return R.error("status 不能为空且必须在 0-3 范围内");
            }
            String screenTag = device.getScreen_tag();
            if (body.get("screen_tag") != null) {
                screenTag = body.get("screen_tag").toString().trim();
            }
            if (body.get("screenTag") != null) {
                screenTag = body.get("screenTag").toString().trim();
            }
            if (!KdsScreenTag.isValid(screenTag)) {
                return R.error("无效的 screen_tag");
            }
            if (!screenTag.equals(device.getScreen_tag())) {
                return R.error(403, "不可操作其他岗位菜品");
            }
            KdsTicket ticket = ticketService.updateItemStatus(
                    device.getShop_id(), detailId, status, screenTag, device.getStation_id());
            return R.ok().put("ticket", ticket);
        } catch (IllegalStateException e) {
            return R.error(401, e.getMessage());
        } catch (Exception e) {
            return R.error(e.getMessage());
        }
    }

    @PostMapping("/lack")
    public R lack(@RequestBody Map<String, Object> body) {
        try {
            KdsDevice device = deviceAuth.requireDevice(request);
            Integer detailId = asInt(body.get("item_id"), body.get("detail_id"), body.get("itemId"));
            if (detailId == null || detailId <= 0) {
                return R.error("item_id/detail_id 不能为空且必须为正整数");
            }
            String remark = body.get("remark") != null ? body.get("remark").toString().trim() : null;
            // 限制remark长度，防止恶意输入
            if (remark != null && remark.length() > 200) {
                remark = remark.substring(0, 200);
            }
            Map<String, Object> result = lackService.reportLack(
                    device.getShop_id(), detailId, device.getScreen_tag(), remark);
            return R.ok(result);
        } catch (IllegalStateException e) {
            return R.error(401, e.getMessage());
        } catch (Exception e) {
            return R.error(e.getMessage());
        }
    }

    private static Integer asInt(Object... candidates) {
        for (Object o : candidates) {
            if (o == null) {
                continue;
            }
            if (o instanceof Number) {
                return ((Number) o).intValue();
            }
            try {
                return Integer.parseInt(o.toString().trim());
            } catch (NumberFormatException ignore) {
                // next
            }
        }
        return null;
    }
}
