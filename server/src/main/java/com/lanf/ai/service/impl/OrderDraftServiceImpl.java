package com.lanf.ai.service.impl;

import com.baomidou.mybatisplus.core.conditions.query.QueryWrapper;
import com.fasterxml.jackson.core.type.TypeReference;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.lanf.ai.dto.AiMenuSnapshotDTO;
import com.lanf.ai.dto.AiMenuSnapshotDTO.AiMenuItemDTO;
import com.lanf.ai.dto.CreateOrderDraftDTO;
import com.lanf.ai.dto.MealLineItemDTO;
import com.lanf.ai.dto.SubmitAiOrderDTO;
import com.lanf.ai.entity.DiningSession;
import com.lanf.ai.entity.MealPlan;
import com.lanf.ai.entity.OrderDraft;
import com.lanf.ai.mapper.DiningSessionMapper;
import com.lanf.ai.mapper.MealPlanMapper;
import com.lanf.ai.mapper.OrderDraftMapper;
import com.lanf.ai.service.IAiMenuAdapterService;
import com.lanf.ai.service.IOrderDraftService;
import com.lanf.common.ApiException;
import com.lanf.entity.Order;
import com.lanf.entity.OrderDetail;
import com.lanf.payment.support.PaymentOrderNoUtil;
import com.lanf.service.IOrderDetailService;
import com.lanf.service.IOrderService;
import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.util.*;

@Slf4j
@Service
public class OrderDraftServiceImpl implements IOrderDraftService {

    @Autowired
    private OrderDraftMapper draftMapper;

    @Autowired
    private MealPlanMapper mealPlanMapper;

    @Autowired
    private DiningSessionMapper sessionMapper;

    @Autowired
    private IAiMenuAdapterService menuAdapterService;

    @Autowired
    private IOrderService orderService;

    @Autowired
    private IOrderDetailService orderDetailService;

    @Autowired(required = false)
    private com.lanf.service.ITableService tableService;

    private final ObjectMapper objectMapper = new ObjectMapper();

    @Override
    @Transactional(rollbackFor = Exception.class)
    public OrderDraft createDraft(CreateOrderDraftDTO dto) {
        if (dto == null || dto.getPlan_id() == null) {
            throw new ApiException(400, "BAD_REQUEST", "方案ID不能为空");
        }
        MealPlan plan = mealPlanMapper.selectOne(new QueryWrapper<MealPlan>().eq("plan_id", dto.getPlan_id()));
        if (plan == null) {
            throw new ApiException(404, "PLAN_NOT_FOUND", "未找到对应配餐方案: " + dto.getPlan_id());
        }

        DiningSession session = sessionMapper.selectOne(new QueryWrapper<DiningSession>().eq("session_id", plan.getSession_id()));
        int shopId = session != null && session.getShop_id() != null ? session.getShop_id() : 1;
        String tableNumber = dto.getTable_number() != null ? dto.getTable_number() : (session != null ? session.getTable_number() : "A01");

        String draftId = "draft_" + UUID.randomUUID().toString().replace("-", "").substring(0, 16);
        OrderDraft draft = new OrderDraft();
        draft.setDraft_id(draftId);
        draft.setPlan_id(plan.getPlan_id());
        draft.setSession_id(plan.getSession_id());
        draft.setShop_id(shopId);
        draft.setTable_number(tableNumber);
        draft.setOpenid(dto.getOpenid());
        draft.setMenu_version(plan.getMenu_version());
        draft.setPrice_total_fen(plan.getPrice_total_fen());
        draft.setItems_snapshot_json(plan.getLine_items_json());
        draft.setValidation_status("PENDING");

        // 草稿 5 分钟有效
        Calendar cal = Calendar.getInstance();
        cal.add(Calendar.MINUTE, 5);
        draft.setExpires_at(cal.getTime());
        draft.setCreated_at(new Date());
        draft.setUpdated_at(new Date());

        draftMapper.insert(draft);
        return draft;
    }

    @Override
    @Transactional(rollbackFor = Exception.class)
    public OrderDraft validateDraft(String draftId) {
        OrderDraft draft = draftMapper.selectOne(new QueryWrapper<OrderDraft>().eq("draft_id", draftId));
        if (draft == null) {
            throw new ApiException(404, "DRAFT_NOT_FOUND", "订单草稿不存在: " + draftId);
        }

        if (draft.getExpires_at() != null && draft.getExpires_at().before(new Date())) {
            draft.setValidation_status("EXPIRED");
            draft.setUpdated_at(new Date());
            draftMapper.updateById(draft);
            return draft;
        }

        // 读取最新菜单快照
        AiMenuSnapshotDTO menuSnapshot = menuAdapterService.getStoreMenuSnapshot(draft.getShop_id());
        if (menuSnapshot == null || menuSnapshot.getMenu_version() == null) {
            draft.setValidation_status("UPSTREAM_UNAVAILABLE");
            draft.setUpdated_at(new Date());
            draftMapper.updateById(draft);
            return draft;
        }

        // 1. 校准菜单版本 Hash 是否发生变动
        if (!menuSnapshot.getMenu_version().equals(draft.getMenu_version())) {
            draft.setValidation_status("PRICE_CHANGED");
            draft.setUpdated_at(new Date());
            draftMapper.updateById(draft);
            return draft;
        }

        // 2. 校准具体菜品在售状态与库存充足度
        Map<Integer, AiMenuItemDTO> itemMap = new HashMap<>();
        for (AiMenuItemDTO m : menuSnapshot.getItems()) {
            itemMap.put(m.getDish_id(), m);
        }

        try {
            List<MealLineItemDTO> items = objectMapper.readValue(draft.getItems_snapshot_json(),
                    new TypeReference<List<MealLineItemDTO>>() {});

            for (MealLineItemDTO item : items) {
                AiMenuItemDTO current = itemMap.get(item.getDish_id());
                if (current == null || !Boolean.TRUE.equals(current.getActive()) || Boolean.TRUE.equals(current.getSold_out())) {
                    draft.setValidation_status("OUT_OF_STOCK");
                    draft.setUpdated_at(new Date());
                    draftMapper.updateById(draft);
                    return draft;
                }
                if (current.getStock() != null && current.getStock() >= 0 && current.getStock() < item.getQuantity()) {
                    draft.setValidation_status("OUT_OF_STOCK");
                    draft.setUpdated_at(new Date());
                    draftMapper.updateById(draft);
                    return draft;
                }
            }
        } catch (Exception e) {
            log.error("Parse draft items error: {}", e.getMessage());
        }

        draft.setValidation_status("PASSED");
        draft.setUpdated_at(new Date());
        draftMapper.updateById(draft);
        return draft;
    }

    @Override
    @Transactional(rollbackFor = Exception.class)
    public Order submitOrder(SubmitAiOrderDTO dto) {
        if (dto == null || dto.getDraft_id() == null) {
            throw new ApiException(400, "BAD_REQUEST", "草稿ID不能为空");
        }
        if (dto.getIdempotency_key() == null || dto.getIdempotency_key().trim().isEmpty()) {
            throw new ApiException(400, "IDEMPOTENCY_KEY_REQUIRED", "下单必须携带幂等键 (idempotency_key)");
        }

        // 幂等防重检查：如果该幂等键已存在且已绑定正式单，直接返回历史订单
        OrderDraft existing = draftMapper.selectOne(new QueryWrapper<OrderDraft>().eq("idempotency_key", dto.getIdempotency_key()));
        if (existing != null && existing.getFormal_order_no() != null) {
            Order order = orderService.getOne(new QueryWrapper<Order>().eq("order_no", existing.getFormal_order_no()));
            if (order != null) {
                log.info("Idempotent hit for key {}: return order {}", dto.getIdempotency_key(), order.getOrder_no());
                return order;
            }
        }

        // 执行二次核价与校库存
        OrderDraft draft = validateDraft(dto.getDraft_id());
        if (!"PASSED".equals(draft.getValidation_status())) {
            throw new ApiException(409, "ORDER_VALIDATION_FAILED", "订单草稿二次核查未通过 (" + draft.getValidation_status() + ")，菜品价格或库存已变动，请重新确认");
        }

        // 创建正式订单
        String orderNo = PaymentOrderNoUtil.generateOrderNo();
        String finalTableNumber = (dto.getTable_number() != null && !dto.getTable_number().trim().isEmpty())
                ? dto.getTable_number().trim()
                : draft.getTable_number();

        Order order = new Order();
        order.setOrder_no(orderNo);
        order.setShop_id(draft.getShop_id());
        order.setTable_number(finalTableNumber);
        order.setSett_amount(draft.getPrice_total_fen() / 100.0);
        order.setDiscount_amount(0.0);
        order.setService_fee(0.0);
        order.setTransac_status("unsettled");
        order.setOrder_receiving("receive");
        order.setDineInOrTakeOut(dto.getDineInOrTakeOut() != null ? dto.getDineInOrTakeOut() : "堂食");
        order.setOrder_channel("ai");
        order.setRemark(dto.getRemark() != null ? dto.getRemark() : "AI智能配餐");
        order.setOpenid(dto.getOpenid() != null ? dto.getOpenid() : draft.getOpenid());
        order.setOrder_time(new Date());
        order.setRevision(1);

        orderService.save(order);

        // 创建明细
        try {
            List<MealLineItemDTO> items = objectMapper.readValue(draft.getItems_snapshot_json(),
                    new TypeReference<List<MealLineItemDTO>>() {});
            List<OrderDetail> details = new ArrayList<>();
            for (MealLineItemDTO item : items) {
                OrderDetail d = new OrderDetail();
                d.setMId(order.getId());
                d.setMorder_no(orderNo);
                d.setDish_id(item.getDish_id());
                d.setName(item.getName());
                d.setQuantity(String.valueOf(item.getQuantity()));
                d.setUnit(item.getUnit());
                d.setTotal_price(item.getSubtotal_fen() / 100.0);
                d.setSelectedSpicy(item.getSpice_level() != null ? item.getSpice_level() : "免辣");
                d.setRemark(item.getKitchen_note());
                d.setLine_status("normal");
                details.add(d);
            }
            orderDetailService.saveBatch(details);
        } catch (Exception e) {
            log.error("Save order details failed: {}", e.getMessage());
            throw new ApiException(500, "CREATE_DETAIL_FAILED", "生成订单明细失败: " + e.getMessage());
        }

        // 若关联了桌台，同步更新桌台状态为就餐中并绑定订单
        if (tableService != null && finalTableNumber != null && !finalTableNumber.trim().isEmpty() && draft.getShop_id() != null) {
            try {
                com.lanf.entity.Table table = tableService.getOne(new QueryWrapper<com.lanf.entity.Table>()
                        .eq("shop_id", draft.getShop_id())
                        .eq("number", finalTableNumber.trim()));
                if (table != null) {
                    table.setStatus(1); // 1: 就餐中
                    table.setOrder_no(orderNo);
                    table.setAmount(order.getSett_amount());
                    table.setOut_time(null);
                    tableService.updateById(table);
                    log.info("Linked table {} to order {}, updated status to 1 (dining)", finalTableNumber, orderNo);
                }
            } catch (Exception te) {
                log.warn("Failed to link table {} to order {}: {}", finalTableNumber, orderNo, te.getMessage());
            }
        }

        // 更新草稿为已确认
        draft.setFormal_order_no(orderNo);
        draft.setValidation_status("CONFIRMED");
        draft.setIdempotency_key(dto.getIdempotency_key());
        draft.setUpdated_at(new Date());
        draftMapper.updateById(draft);

        return order;
    }
}
