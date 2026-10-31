package com.lanf.kds.controller;

import com.baomidou.mybatisplus.core.conditions.query.QueryWrapper;
import com.lanf.entity.R;
import com.lanf.kds.KdsItemStatus;
import com.lanf.kds.KdsScreenTag;
import com.lanf.kds.entity.KdsDevice;
import com.lanf.kds.entity.KdsTicket;
import com.lanf.kds.mapper.KdsTicketMapper;
import com.lanf.kds.service.KdsOrderListService;
import com.lanf.kds.service.KdsTicketFlagService;
import com.lanf.kds.service.KdsTicketService;
import com.lanf.kds.service.KdsWorkflowService;
import com.lanf.kds.util.KdsDeviceAuth;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.web.bind.annotation.*;

import javax.servlet.http.HttpServletRequest;
import java.util.List;
import java.util.Map;

@RestController
@RequestMapping("/kds/order")
public class KdsOrderController {

    @Autowired
    private KdsDeviceAuth deviceAuth;
    @Autowired
    private KdsOrderListService orderListService;
    @Autowired
    private KdsTicketMapper ticketMapper;
    @Autowired
    private KdsTicketService ticketService;
    @Autowired
    private KdsTicketFlagService ticketFlagService;
    @Autowired
    private HttpServletRequest request;

    @Autowired
    private KdsWorkflowService workflowService;

    @GetMapping("/item/list")
    public R itemList(@RequestParam(required = false) String queue,
                      @RequestParam(required = false) String dining,
                      @RequestParam(required = false) String extra,
                      @RequestParam(required = false) String keyword) {
        try {
            KdsDevice device = deviceAuth.requireDevice(request);
            return R.ok(workflowService.listOrderItems(device, queue, dining, extra, keyword));
        } catch (IllegalStateException e) {
            return R.error(401, e.getMessage());
        } catch (Exception e) {
            return R.error(e.getMessage());
        }
    }

    @GetMapping("/list")
    public R list(@RequestParam(required = false) String screen_tag,
                  @RequestParam(required = false) String screenTag,
                  @RequestParam(required = false) Integer status,
                  @RequestParam(required = false, defaultValue = "1") Integer page,
                  @RequestParam(required = false, defaultValue = "50") Integer pageSize,
                  @RequestParam(required = false, defaultValue = "false") Boolean includeArchived) {
        try {
            KdsDevice device = deviceAuth.requireDevice(request);
            String tag = screen_tag != null ? screen_tag : screenTag;
            if (tag == null) {
                tag = device.getScreen_tag();
            }
            if (!KdsScreenTag.isValid(tag)) {
                return R.error("无效的 screen_tag");
            }
            if (!tag.equals(device.getScreen_tag())) {
                return R.error(403, "不可查询其他岗位队列");
            }
            // 验证分页参数
            if (page == null || page < 1) {
                page = 1;
            }
            if (pageSize == null || pageSize < 1) {
                pageSize = 50;
            }
            pageSize = Math.min(pageSize, 50);
            List<Map<String, Object>> cards = orderListService.listOrderCards(
                    device.getShop_id(), tag, status, Boolean.TRUE.equals(includeArchived),
                    page, pageSize);
            return R.ok().put("orders", cards).put("screen_tag", tag);
        } catch (IllegalStateException e) {
            return R.error(401, e.getMessage());
        } catch (Exception e) {
            return R.error(e.getMessage());
        }
    }

    @PostMapping("/rush")
    public R rush(@RequestBody Map<String, Object> body) {
        try {
            KdsDevice device = deviceAuth.requireDevice(request);
            Integer orderId = asInt(body.get("orderId"), body.get("order_id"));
            if (orderId == null) {
                return R.error("order_id 不能为空");
            }
            Integer detailId = asInt(body.get("detailId"), body.get("detail_id"));
            Map<String, Object> result = ticketFlagService.rushOrder(device.getShop_id(), orderId, detailId);
            return R.ok(result);
        } catch (IllegalStateException e) {
            return R.error(401, e.getMessage());
        } catch (Exception e) {
            return R.error(e.getMessage());
        }
    }

    @PostMapping("/finish-all")
    public R finishAll(@RequestBody Map<String, Object> body) {
        try {
            KdsDevice device = deviceAuth.requireDevice(request);
            Integer orderId = asInt(body.get("orderId"), body.get("order_id"));
            if (orderId == null) {
                return R.error("order_id 不能为空");
            }
            List<KdsTicket> tickets = ticketMapper.selectList(new QueryWrapper<KdsTicket>()
                    .eq("shop_id", device.getShop_id())
                    .eq("order_id", orderId)
                    .eq("screen_tag", device.getScreen_tag())
                    .in("item_status", KdsItemStatus.PENDING, KdsItemStatus.COOKING));
            for (KdsTicket t : tickets) {
                ticketService.updateItemStatus(device.getShop_id(), t.getDetail_id(),
                        KdsItemStatus.DONE, device.getScreen_tag(), device.getStation_id());
            }
            return R.ok().put("done", tickets.size());
        } catch (IllegalStateException e) {
            return R.error(401, e.getMessage());
        } catch (Exception e) {
            return R.error(e.getMessage());
        }
    }

    private static Integer asInt(Object a, Object b) {
        Object o = a != null ? a : b;
        if (o instanceof Number) {
            return ((Number) o).intValue();
        }
        if (o != null) {
            try {
                return Integer.parseInt(o.toString().trim());
            } catch (NumberFormatException e) {
                return null;
            }
        }
        return null;
    }
}
