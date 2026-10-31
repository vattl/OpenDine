package com.lanf.kds;

import com.baomidou.mybatisplus.core.conditions.query.QueryWrapper;
import com.lanf.entity.Order;
import com.lanf.entity.OrderDetail;
import com.lanf.kds.entity.KdsDevice;
import com.lanf.kds.entity.KdsShopConfig;
import com.lanf.kds.entity.KdsTicket;
import com.lanf.kds.mapper.KdsTicketMapper;
import com.lanf.kds.service.*;
import com.lanf.service.IOrderDetailService;
import org.junit.jupiter.api.Assumptions;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.condition.EnabledIfEnvironmentVariable;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.context.ActiveProfiles;

import java.util.List;
import java.util.Map;

import static org.junit.jupiter.api.Assertions.*;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

/**
 * 独立 debug 库冒烟：默认门店 shop_id=1（订单量最多的测试店）。
 * 显式设置 RUN_LOCAL_KDS_SMOKE=true 才运行，避免常规测试连接或写入生产数据库。
 */
@SpringBootTest
@AutoConfigureMockMvc
@ActiveProfiles("debug")
@EnabledIfEnvironmentVariable(named = "RUN_LOCAL_KDS_SMOKE", matches = "(?i)true")
class KdsLocalSmokeTest {

    private static final int SHOP_ID = 1;

    @Autowired
    private MockMvc mockMvc;
    @Autowired
    private KdsStationService stationService;
    @Autowired
    private KdsConfigService configService;
    @Autowired
    private KdsDeviceService deviceService;
    @Autowired
    private KdsTicketService ticketService;
    @Autowired
    private KdsTicketMapper ticketMapper;
    @Autowired
    private JdbcTemplate jdbcTemplate;
    @Autowired
    private IOrderDetailService orderDetailService;

    @Test
    void smokeShop1_kdsFlow() throws Exception {
        assumeDbReady();

        stationService.initFiveScreens(SHOP_ID);
        KdsShopConfig cfg = configService.getOrDefault(SHOP_ID);
        cfg.setKds_mode(KdsConfigService.MODE_BOTH);
        cfg.setAuto_push_on_create(1);
        configService.save(SHOP_ID, cfg);

        Map<String, Object> row = jdbcTemplate.queryForList(
                "SELECT DISTINCT o.id, o.order_no, o.shop_id, o.orderNumber FROM t_order o "
                        + "JOIN t_order_detail d ON d.mId = o.id "
                        + "LEFT JOIN t_kds_ticket k ON k.shop_id = o.shop_id AND k.detail_id = d.id "
                        + "WHERE o.shop_id = ? AND o.transac_status = 'success' "
                        + "AND (k.id IS NULL OR (k.item_status = 0 AND k.archived = 0)) "
                        + "ORDER BY o.id DESC LIMIT 1",
                SHOP_ID).stream().findFirst().orElse(null);
        Assumptions.assumeTrue(row != null, "门店1需至少一笔尚可执行 0 -> 1 的真实 success 订单明细");
        Order order = new Order();
        order.setId(((Number) row.get("id")).intValue());
        order.setOrder_no(row.get("order_no") != null ? row.get("order_no").toString() : null);
        order.setShop_id(row.get("shop_id") != null ? ((Number) row.get("shop_id")).intValue() : SHOP_ID);
        Object on = row.get("orderNumber");
        if (on != null) {
            order.setOrderNumber(on instanceof Number ? ((Number) on).intValue() : Integer.parseInt(on.toString()));
        }
        List<OrderDetail> details = orderDetailService.list(new QueryWrapper<OrderDetail>()
                .eq("mId", order.getId()));
        assertFalse(details.isEmpty(), "订单需有明细");

        ticketService.createTicketsForOrder(order, null, KdsOrderHook.Trigger.CREATE);
        List<KdsTicket> tickets = ticketMapper.selectList(new QueryWrapper<KdsTicket>()
                .eq("order_id", order.getId())
                .eq("item_status", 0)
                .eq("archived", 0)
                .orderByAsc("id"));
        Assumptions.assumeFalse(tickets.isEmpty(), "选中订单需有尚可执行 0 -> 1 的真实 KDS 工单");
        KdsTicket testTicket = tickets.get(0);
        assertNotNull(testTicket.getDetail_id(), "KDS 工单需关联真实订单明细");
        assertNotNull(testTicket.getScreen_tag(), "KDS 工单需分配真实屏幕");

        KdsDevice device = deviceService.bind(
                SHOP_ID, "KDS-JUNIT-SMOKE", "JUnit屏", testTicket.getScreen_tag());
        assertNotNull(device.getDevice_token());

        mockMvc.perform(get("/kds/order/list").param("status", "0")
                        .header("X-Kds-Device-Token", device.getDevice_token()))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.code").value(0));

        mockMvc.perform(get("/kds/stats/today")
                        .header("X-Kds-Device-Token", device.getDevice_token()))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.code").value(0))
                .andExpect(jsonPath("$.stats.ticket_count").isNumber());

        Integer detailId = testTicket.getDetail_id();
        mockMvc.perform(post("/kds/item/status")
                        .header("X-Kds-Device-Token", device.getDevice_token())
                        .contentType("application/json")
                        .content("{\"detail_id\":" + detailId + ",\"status\":1,\"screen_tag\":\""
                                + testTicket.getScreen_tag() + "\"}"))
                .andExpect(status().isGone())
                .andExpect(jsonPath("$.code").value(410));
    }

    private void assumeDbReady() {
        try {
            stationService.listByShop(SHOP_ID);
        } catch (Exception e) {
            Assumptions.assumeTrue(false, "数据库不可用或未执行 KDS 迁移: " + e.getMessage());
        }
    }
}
