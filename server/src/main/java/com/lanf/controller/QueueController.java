package com.lanf.controller;

import com.baomidou.mybatisplus.core.conditions.query.QueryWrapper;
import com.lanf.entity.QueueTicket;
import com.lanf.entity.R;
import com.lanf.entity.Shop;
import com.lanf.entity.SystemConfig;
import com.lanf.mapper.QueueTicketMapper;
import com.lanf.mapper.ShopMapper;
import com.lanf.mapper.SystemConfigMapper;
import com.lanf.interceptor.UserIdentityInterceptor;
import com.lanf.service.IShopService;
import com.lanf.util.ShopChainSupport;
import com.lanf.util.StringUtil;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.web.bind.annotation.*;

import javax.servlet.http.HttpServletRequest;
import java.text.SimpleDateFormat;
import java.util.*;

/**
 * C 端排队取号接口。
 */
@RestController
@RequestMapping("/queue")
public class QueueController {

    private static final int DEFAULT_C_SHOP_ID = 1;
    private static final String STATUS_WAITING = "waiting";
    private static final String STATUS_CALLING = "calling";
    private static final String STATUS_SEATED = "seated";
    private static final String STATUS_CANCELLED = "cancelled";
    private static final String STATUS_EXPIRED = "expired";

    @Autowired
    private QueueTicketMapper queueTicketMapper;
    @Autowired
    private SystemConfigMapper systemConfigMapper;
    @Autowired
    private ShopMapper shopMapper;
    @Autowired
    private IShopService shopService;

    @GetMapping("/config")
    public R getConfig(@RequestParam(name = "shop_id", required = false) Integer shopId,
                       @RequestParam(name = "shop_code", required = false) String shopCode,
                       HttpServletRequest request) {
        Integer resolvedShopId;
        try {
            resolvedShopId = resolveShopId(request, shopId, shopCode);
        } catch (RuntimeException e) {
            return R.error(e.getMessage());
        }
        Map<String, Object> data = new HashMap<>();
        data.put("enabled", parseBooleanConfig(getConfigOrDefault(resolvedShopId, "queue.enabled", "true"), true));
        data.put("shopName", getShopName(resolvedShopId));
        data.put("notice", getConfigOrDefault(resolvedShopId, "queue.notice", ""));
        return R.ok().put("msg", "ok").put("data", data);
    }

    @PostMapping("/ticket/create")
    public R createTicket(@RequestBody Map<String, Object> body, HttpServletRequest request) {
        if (body == null) {
            return R.error("请求体不能为空");
        }
        Integer resolvedShopId;
        try {
            resolvedShopId = resolveShopId(request,
                    ShopChainSupport.parseBodyShopId(body.get("shop_id")),
                    ShopChainSupport.parseBodyShopCode(body.get("shop_code")));
        } catch (RuntimeException e) {
            return R.error(e.getMessage());
        }
        String openid = trimToNull(body.get("openid"));
        String mobile = trimToNull(body.get("mobile"));
        String dineType = trimToNull(body.get("dineType"));
        String remark = trimToEmpty(body.get("remark"));
        Integer partySize = parseInt(body.get("partySize"));
        if (StringUtil.isEmpty(openid)) {
            return R.error("openid 不能为空");
        }
        if (StringUtil.isEmpty(mobile)) {
            return R.error("mobile 不能为空");
        }
        if (partySize == null || partySize <= 0) {
            return R.error("partySize 必须大于 0");
        }
        if (StringUtil.isEmpty(dineType)) {
            return R.error("dineType 不能为空");
        }

        QueueTicket ticket = new QueueTicket();
        ticket.setTicket_no(generateTicketNo(resolvedShopId));
        ticket.setOpenid(openid);
        ticket.setMobile(mobile);
        ticket.setParty_size(partySize);
        ticket.setDine_type(dineType);
        ticket.setRemark(remark);
        ticket.setShop_id(resolvedShopId);
        ticket.setStatus(STATUS_WAITING);
        Date now = new Date();
        ticket.setCreated_at(now);
        ticket.setUpdated_at(now);
        queueTicketMapper.insert(ticket);

        int aheadCount = countAhead(ticket.getId(), resolvedShopId);
        Map<String, Object> data = new HashMap<>();
        data.put("ticketNo", ticket.getTicket_no());
        data.put("shopId", resolvedShopId);
        data.put("status", ticket.getStatus());
        data.put("aheadCount", aheadCount);
        data.put("estimatedWaitMinutes", estimateWaitMinutes(aheadCount));
        data.put("createdAt", formatDateTime(ticket.getCreated_at()));
        return R.ok().put("msg", "ok").put("data", data);
    }

    @GetMapping("/ticket/status")
    public R ticketStatus(@RequestParam("ticketNo") String ticketNo,
                          @RequestParam(name = "shop_id", required = false) Integer shopId,
                          @RequestParam(name = "shop_code", required = false) String shopCode,
                          HttpServletRequest request) {
        if (StringUtil.isEmpty(ticketNo)) {
            return R.error("ticketNo 不能为空");
        }
        Integer resolvedShopId;
        try {
            resolvedShopId = resolveShopId(request, shopId, shopCode);
        } catch (RuntimeException e) {
            return R.error(e.getMessage());
        }
        QueueTicket ticket = queueTicketMapper.selectOne(
                new QueryWrapper<QueueTicket>().eq("ticket_no", ticketNo.trim()).eq("shop_id", resolvedShopId)
                        .eq("openid", authenticatedOpenid(request)));
        if (ticket == null) {
            return R.error("排队号不存在");
        }
        int aheadCount = isActive(ticket.getStatus()) ? countAhead(ticket.getId(), resolvedShopId) : 0;
        Map<String, Object> data = new HashMap<>();
        data.put("ticketNo", ticket.getTicket_no());
        data.put("shopId", resolvedShopId);
        data.put("status", ticket.getStatus());
        data.put("aheadCount", aheadCount);
        data.put("estimatedWaitMinutes", isActive(ticket.getStatus()) ? estimateWaitMinutes(aheadCount) : 0);
        data.put("createdAt", formatDateTime(ticket.getCreated_at()));
        return R.ok().put("msg", "ok").put("data", data);
    }

    @PostMapping("/ticket/cancel")
    public R cancel(@RequestBody Map<String, Object> body, HttpServletRequest request) {
        if (body == null) {
            return R.error("请求体不能为空");
        }
        Integer resolvedShopId;
        try {
            resolvedShopId = resolveShopId(request,
                    ShopChainSupport.parseBodyShopId(body.get("shop_id")),
                    ShopChainSupport.parseBodyShopCode(body.get("shop_code")));
        } catch (RuntimeException e) {
            return R.error(e.getMessage());
        }
        String ticketNo = trimToNull(body.get("ticketNo"));
        if (StringUtil.isEmpty(ticketNo)) {
            return R.error("ticketNo 不能为空");
        }
        QueueTicket ticket = queueTicketMapper.selectOne(
                new QueryWrapper<QueueTicket>().eq("ticket_no", ticketNo).eq("shop_id", resolvedShopId)
                        .eq("openid", authenticatedOpenid(request)));
        if (ticket == null) {
            return R.error("排队号不存在");
        }
        if (STATUS_CANCELLED.equals(ticket.getStatus())) {
            return R.ok().put("msg", "已取消").put("data", new HashMap<>());
        }
        if (STATUS_SEATED.equals(ticket.getStatus())) {
            return R.error("已入座，无法取消");
        }
        ticket.setStatus(STATUS_CANCELLED);
        ticket.setUpdated_at(new Date());
        queueTicketMapper.updateById(ticket);
        return R.ok().put("msg", "已取消").put("data", new HashMap<>());
    }

    private synchronized String generateTicketNo(Integer shopId) {
        List<QueueTicket> list = queueTicketMapper.selectList(
                new QueryWrapper<QueueTicket>()
                        .select("ticket_no")
                        .eq("shop_id", shopId)
                        .likeRight("ticket_no", "A")
                        .orderByDesc("id")
                        .last("limit 1"));
        int seq = 100;
        if (!list.isEmpty() && !StringUtil.isEmpty(list.get(0).getTicket_no())) {
            String no = list.get(0).getTicket_no().trim();
            if (no.length() > 1) {
                try {
                    seq = Integer.parseInt(no.substring(1)) + 1;
                } catch (Exception ignore) {
                    seq = 100;
                }
            }
        }
        return "A" + seq;
    }

    private int countAhead(Long currentId, Integer shopId) {
        if (currentId == null) {
            return 0;
        }
        return Math.toIntExact(queueTicketMapper.selectCount(
                new QueryWrapper<QueueTicket>()
                        .eq("shop_id", shopId)
                        .lt("id", currentId)
                        .in("status", STATUS_WAITING, STATUS_CALLING)));
    }

    private boolean isActive(String status) {
        return STATUS_WAITING.equals(status) || STATUS_CALLING.equals(status);
    }

    private int estimateWaitMinutes(int aheadCount) {
        if (aheadCount <= 0) {
            return 0;
        }
        return aheadCount * 4 + 4;
    }

    private String getShopName(Integer shopId) {
        String configShopName = getConfigOrDefault(shopId, "queue.shopName", null);
        if (!StringUtil.isEmpty(configShopName)) {
            return configShopName;
        }
        Shop targetShop = shopMapper.selectOne(new QueryWrapper<Shop>()
                .select("id", "name", "status")
                .eq("id", shopId)
                .eq("status", 1)
                .last("limit 1"));
        if (targetShop != null && !StringUtil.isEmpty(targetShop.getName())) {
            return targetShop.getName();
        }
        return "门店";
    }

    private String getConfigOrDefault(Integer shopId, String key, String def) {
        if (shopId != null) {
            String shopKey = key + "." + shopId;
            SystemConfig shopOne = systemConfigMapper.selectOne(new QueryWrapper<SystemConfig>().eq("config_key", shopKey));
            if (shopOne != null && shopOne.getConfig_value() != null) {
                return shopOne.getConfig_value();
            }
        }
        SystemConfig one = systemConfigMapper.selectOne(new QueryWrapper<SystemConfig>().eq("config_key", key));
        if (one == null || one.getConfig_value() == null) {
            return def;
        }
        return one.getConfig_value();
    }

    private boolean parseBooleanConfig(String raw, boolean def) {
        if (StringUtil.isEmpty(raw)) {
            return def;
        }
        String s = raw.trim();
        if ("1".equals(s) || "true".equalsIgnoreCase(s)) {
            return true;
        }
        if ("0".equals(s) || "false".equalsIgnoreCase(s)) {
            return false;
        }
        return def;
    }

    private Integer resolveShopId(HttpServletRequest request, Integer shopId, String shopCode) {
        Integer resolved = ShopChainSupport.resolveShopChain(request, shopId,
                shopCode != null ? shopCode.trim() : null,
                shopService::requireActiveShopIdByCode);
        if (resolved == null) {
            resolved = DEFAULT_C_SHOP_ID;
        }
        Shop active = shopMapper.selectOne(new QueryWrapper<Shop>()
                .select("id", "status")
                .eq("id", resolved)
                .eq("status", 1)
                .last("limit 1"));
        if (active == null) {
            throw new RuntimeException("门店不可用或不存在");
        }
        return resolved;
    }

    private Integer parseInt(Object raw) {
        if (raw instanceof Number) {
            return ((Number) raw).intValue();
        }
        if (raw == null || StringUtil.isEmpty(raw.toString())) {
            return null;
        }
        try {
            return Integer.parseInt(raw.toString().trim());
        } catch (Exception ignore) {
            return null;
        }
    }

    private String trimToNull(Object raw) {
        if (raw == null) {
            return null;
        }
        String s = raw.toString().trim();
        return StringUtil.isEmpty(s) ? null : s;
    }

    private String trimToEmpty(Object raw) {
        return raw == null ? "" : raw.toString().trim();
    }

    private String formatDateTime(Date date) {
        if (date == null) {
            return null;
        }
        return new SimpleDateFormat("yyyy-MM-dd HH:mm:ss").format(date);
    }

    private String authenticatedOpenid(HttpServletRequest request) {
        Object value = request.getAttribute(UserIdentityInterceptor.ATTR_USER_OPENID);
        if (value == null || StringUtil.isEmpty(value.toString())) {
            throw new IllegalStateException("用户身份缺失");
        }
        return value.toString();
    }
}
