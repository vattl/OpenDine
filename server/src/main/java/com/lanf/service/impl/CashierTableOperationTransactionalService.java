package com.lanf.service.impl;

import com.fasterxml.jackson.core.JsonProcessingException;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.lanf.dto.CashierTableOperationRequest;
import com.lanf.dto.CashierTableOperationResult;
import com.lanf.entity.CashierTableAudit;
import com.lanf.entity.Order;
import com.lanf.entity.Table;
import com.lanf.mapper.CashierTableAuditMapper;
import com.lanf.mapper.CashierTableOperationMapper;
import com.lanf.util.OrderNetRevenue;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Isolation;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.util.StringUtils;

import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.util.ArrayList;
import java.util.Collections;
import java.util.Date;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.stream.Collectors;

@Service
public class CashierTableOperationTransactionalService {

    private static final org.slf4j.Logger log = org.slf4j.LoggerFactory.getLogger(CashierTableOperationTransactionalService.class);
    private static final String MODULE = "cashier_table";
    private static final int TABLE_NUMBER_MAX_LENGTH = 20;
    private final CashierTableOperationMapper operationMapper;
    private final CashierTableAuditMapper auditMapper;
    private final ObjectMapper objectMapper;
    private final com.lanf.kds.delivery.CashierKdsProjectionService projectionService;
    private final com.lanf.printing.service.PrintDispatcherService printDispatcherService;

    public CashierTableOperationTransactionalService(CashierTableOperationMapper operationMapper,
                                                      CashierTableAuditMapper auditMapper,
                                                      ObjectMapper objectMapper) {
        this(operationMapper, auditMapper, objectMapper, null, null);
    }

    public CashierTableOperationTransactionalService(CashierTableOperationMapper operationMapper,
                                                      CashierTableAuditMapper auditMapper,
                                                      ObjectMapper objectMapper,
                                                      com.lanf.kds.delivery.CashierKdsProjectionService projectionService) {
        this(operationMapper, auditMapper, objectMapper, projectionService, null);
    }

    @org.springframework.beans.factory.annotation.Autowired
    public CashierTableOperationTransactionalService(CashierTableOperationMapper operationMapper,
                                                      CashierTableAuditMapper auditMapper,
                                                      ObjectMapper objectMapper,
                                                      @org.springframework.beans.factory.annotation.Autowired(required = false)
                                                      com.lanf.kds.delivery.CashierKdsProjectionService projectionService,
                                                      @org.springframework.beans.factory.annotation.Autowired(required = false)
                                                      com.lanf.printing.service.PrintDispatcherService printDispatcherService) {
        this.operationMapper = operationMapper;
        this.auditMapper = auditMapper;
        this.objectMapper = objectMapper;
        this.projectionService = projectionService;
        this.printDispatcherService = printDispatcherService;
    }

    @Transactional(rollbackFor = Exception.class, isolation = Isolation.SERIALIZABLE)
    public CashierTableOperationResult execute(CashierTableOperationRequest request) {
        normalize(request);
        String fingerprint = fingerprint(request);
        CashierTableAudit previous = auditMapper.findByRequest(
                request.getShopId(), request.getAction(), request.getRequestKey());
        if (previous != null) {
            if (!fingerprint.equals(previous.getRequest_fingerprint())) {
                return CashierTableOperationResult.rejected(409, "幂等标识已被其他请求使用");
            }
            CashierTableOperationResult replay = "SUCCESS".equals(previous.getResult_status())
                    ? CashierTableOperationResult.success(previous.getReason(), null)
                    : CashierTableOperationResult.rejected(
                            previous.getResult_code() == null ? 409 : previous.getResult_code(), previous.getReason());
            replay.setIdempotent(true);
            return replay;
        }

        CashierTableAudit audit = baseAudit(request, fingerprint);
        CashierTableOperationResult result;
        switch (request.getAction()) {
            case "OPEN":
                result = open(request, audit);
                break;
            case "CLEAR":
                result = clear(request, audit);
                break;
            case "MERGE":
                result = merge(request, audit);
                break;
            case "TRANSFER":
                result = transfer(request, audit);
                break;
            default:
                result = CashierTableOperationResult.rejected(400, "不支持的桌台操作");
                finishAudit(audit, result, Collections.emptyMap());
        }
        auditMapper.insert(audit);
        return result;
    }

    private CashierTableOperationResult open(CashierTableOperationRequest request, CashierTableAudit audit) {
        if (!StringUtils.hasText(request.getSourceTable())) {
            return reject(audit, 400, "桌号不能为空", Collections.emptyList(), Collections.emptyMap(), Collections.emptyMap());
        }
        if (request.getSourceTable().length() > TABLE_NUMBER_MAX_LENGTH) {
            return reject(audit, 400, "桌号长度不能超过20个字符",
                    Collections.emptyList(), Collections.emptyMap(), Collections.emptyMap());
        }
        Table table = operationMapper.lockTable(request.getShopId(), request.getSourceTable());
        List<Order> unsettled = operationMapper.lockUnsettledOrders(request.getShopId(), request.getSourceTable());
        Map<String, Object> before = state(table, unsettled);
        audit.setBefore_state(json(before));
        audit.setOrder_nos(json(orderNos(unsettled)));
        if (!unsettled.isEmpty()) {
            return reject(audit, 409, "桌台存在未结账订单，无法开台", unsettled, before, before);
        }
        if (table != null && !Integer.valueOf(0).equals(table.getStatus())) {
            String message = Integer.valueOf(2).equals(table.getStatus())
                    ? "桌台已结账待清台，请先完成清台"
                    : "桌台状态非空闲，无法开台";
            return reject(audit, 409, message, unsettled, before, before);
        }

        Date now = new Date();
        if (table == null) {
            table = new Table();
            table.setShop_id(request.getShopId());
            table.setNumber(request.getSourceTable());
            table.setStatus(1);
            table.setOpen_time(now);
            table.setAmount(0D);
            if (operationMapper.insertTable(table) != 1) {
                throw new IllegalStateException("开台写入失败");
            }
        } else {
            int oldStatus = table.getStatus() == null ? 0 : table.getStatus();
            if (operationMapper.openExistingTable(table.getId(), request.getShopId(), oldStatus, now) != 1) {
                throw new IllegalStateException("桌台状态已变化，请重试");
            }
            table.setStatus(1);
            table.setOpen_time(now);
            table.setOut_time(null);
            table.setOrder_no(null);
            table.setAmount(0D);
        }
        CashierTableOperationResult result = CashierTableOperationResult.success("开台成功", table);
        finishAudit(audit, result, state(table, Collections.emptyList()));
        return result;
    }

    private CashierTableOperationResult clear(CashierTableOperationRequest request, CashierTableAudit audit) {
        if (!StringUtils.hasText(request.getSourceTable())) {
            return reject(audit, 400, "桌号不能为空", Collections.emptyList(), Collections.emptyMap(), Collections.emptyMap());
        }
        if (request.getSourceTable().length() > TABLE_NUMBER_MAX_LENGTH) {
            return reject(audit, 400, "桌号长度不能超过20个字符",
                    Collections.emptyList(), Collections.emptyMap(), Collections.emptyMap());
        }
        Table table = operationMapper.lockTable(request.getShopId(), request.getSourceTable());
        List<Order> unsettled = operationMapper.lockUnsettledOrders(request.getShopId(), request.getSourceTable());
        Map<String, Object> before = state(table, unsettled);
        audit.setBefore_state(json(before));
        audit.setOrder_nos(json(orderNos(unsettled)));
        if (table == null) {
            return reject(audit, 404, "当前门店不存在该桌台", unsettled, before, before);
        }
        if (!unsettled.isEmpty()) {
            return reject(audit, 409, "该桌仍有 " + unsettled.size() + " 笔未结账订单，无法清台",
                    unsettled, before, before);
        }
        if (Integer.valueOf(0).equals(table.getStatus())) {
            CashierTableOperationResult result = CashierTableOperationResult.success("桌台已为空闲状态", table);
            result.setIdempotent(true);
            finishAudit(audit, result, before);
            return result;
        }
        if (!Integer.valueOf(1).equals(table.getStatus()) && !Integer.valueOf(2).equals(table.getStatus())) {
            return reject(audit, 409, "桌台状态异常，无法清台", unsettled, before, before);
        }
        Date now = new Date();
        int expectedStatus = table.getStatus();
        if (operationMapper.clearTable(table.getId(), request.getShopId(), expectedStatus, now) != 1) {
            throw new IllegalStateException("桌台状态已变化，请重试");
        }
        table.setStatus(0);
        table.setOut_time(now);
        table.setOrder_no(null);
        table.setAmount(0D);
        operationMapper.finishSettledOrdersOnTable(request.getShopId(), request.getSourceTable(), now);
        CashierTableOperationResult result = CashierTableOperationResult.success("清台成功", table);
        finishAudit(audit, result, state(table, Collections.emptyList()));
        return result;
    }

    private CashierTableOperationResult merge(CashierTableOperationRequest request, CashierTableAudit audit) {
        if (!StringUtils.hasText(request.getSourceTable()) || !StringUtils.hasText(request.getTargetTable())
                || request.getSourceTable().equals(request.getTargetTable())) {
            return reject(audit, 400, "源桌号与目标桌号不能为空且不能相同",
                    Collections.emptyList(), Collections.emptyMap(), Collections.emptyMap());
        }
        if (request.getSourceTable().length() > TABLE_NUMBER_MAX_LENGTH
                || request.getTargetTable().length() > TABLE_NUMBER_MAX_LENGTH) {
            return reject(audit, 400, "桌号长度不能超过20个字符",
                    Collections.emptyList(), Collections.emptyMap(), Collections.emptyMap());
        }
        List<Table> locked = operationMapper.lockTables(
                request.getShopId(), request.getSourceTable(), request.getTargetTable());
        Table source = findTable(locked, request.getSourceTable());
        Table target = findTable(locked, request.getTargetTable());
        List<Order> sourceOrders = source == null ? Collections.emptyList()
                : operationMapper.lockUnsettledOrders(request.getShopId(), request.getSourceTable());
        List<Order> targetOrders = target == null ? Collections.emptyList()
                : operationMapper.lockUnsettledOrders(request.getShopId(), request.getTargetTable());
        List<Order> allOrders = new ArrayList<>(sourceOrders);
        allOrders.addAll(targetOrders);
        Map<String, Object> before = mergeState(source, target, sourceOrders, targetOrders);
        audit.setBefore_state(json(before));
        audit.setOrder_nos(json(orderNos(allOrders)));

        if (source == null || target == null) {
            return reject(audit, 404, "当前门店的源桌或目标桌不存在", allOrders, before, before);
        }
        if (!Integer.valueOf(1).equals(source.getStatus())) {
            return reject(audit, 409, "源桌未开台，无法并台", allOrders, before, before);
        }
        if (!Integer.valueOf(1).equals(target.getStatus())) {
            return reject(audit, 409, "目标桌未开台，无法并台", allOrders, before, before);
        }
        if (sourceOrders.isEmpty()) {
            return reject(audit, 409, "源桌没有未结账订单，无法并台", allOrders, before, before);
        }

        String pointer = containsOrderNo(targetOrders, target.getOrder_no())
                ? target.getOrder_no()
                : (!targetOrders.isEmpty() ? targetOrders.get(0).getOrder_no() : sourceOrders.get(0).getOrder_no());
        int moved = operationMapper.moveUnsettledOrders(
                request.getShopId(), request.getSourceTable(), request.getTargetTable(), pointer);
        if (moved != sourceOrders.size()) {
            throw new IllegalStateException("订单状态已变化，并台已回滚，请重试");
        }
        Date now = new Date();
        if (operationMapper.clearTable(source.getId(), request.getShopId(), 1, now) != 1) {
            throw new IllegalStateException("源桌状态已变化，并台已回滚，请重试");
        }
        operationMapper.finishSettledOrdersOnTable(request.getShopId(), request.getSourceTable(), now);
        double targetAmount = outstandingAmount(allOrders);
        if (operationMapper.updateTableState(target.getId(), request.getShopId(), 1, pointer,
                targetAmount, target.getOpen_time(), null) != 1) {
            throw new IllegalStateException("目标桌状态已变化，并台已回滚，请重试");
        }
        target.setOrder_no(pointer);
        target.setAmount(targetAmount);
        source.setStatus(0);
        source.setOut_time(now);
        source.setOrder_no(null);
        for (Order order : sourceOrders) {
            order.setTable_number(request.getTargetTable());
            order.setMaster_order_no(pointer);
            if (projectionService != null && order.getId() != null) {
                projectionService.publishAfterCommit(order.getId(), "ORDER_UPDATED", null, null, null);
            }
        }
        dispatchTableChangePrint(request.getShopId(), "并台", request.getSourceTable(), request.getTargetTable(),
                orderNos(sourceOrders), request.getOperatorId());
        CashierTableOperationResult result = CashierTableOperationResult.success(
                "并台成功；目标桌原有订单保留，源桌订单已追加", target);
        finishAudit(audit, result, mergeState(source, target, Collections.emptyList(), allOrders));
        audit.setOrder_nos(json(orderNos(allOrders)));
        return result;
    }

    private CashierTableOperationResult transfer(CashierTableOperationRequest request, CashierTableAudit audit) {
        if (!StringUtils.hasText(request.getOrderNo()) || !StringUtils.hasText(request.getTargetTable())) {
            return reject(audit, 400, "订单号与目标桌号不能为空",
                    Collections.emptyList(), Collections.emptyMap(), Collections.emptyMap());
        }
        Order snapshot = operationMapper.findOrder(request.getShopId(), request.getOrderNo());
        if (snapshot == null || !StringUtils.hasText(snapshot.getTable_number())) {
            return reject(audit, 404, "当前门店不存在该桌台订单",
                    Collections.emptyList(), Collections.emptyMap(), Collections.emptyMap());
        }
        request.setSourceTable(snapshot.getTable_number());
        audit.setSource_table(auditText(request.getSourceTable(), 50));
        audit.setTarget_id(auditText(request.getOrderNo(), 64));
        Map<String, Object> requestSnapshot = new LinkedHashMap<>();
        requestSnapshot.put("sourceTable", auditText(request.getSourceTable(), 50));
        requestSnapshot.put("targetTable", auditText(request.getTargetTable(), 50));
        requestSnapshot.put("orderNo", auditText(request.getOrderNo(), 64));
        audit.setRequest_snapshot(json(requestSnapshot));
        if (request.getSourceTable().equals(request.getTargetTable())) {
            return reject(audit, 400, "源桌号与目标桌号不能相同",
                    Collections.singletonList(snapshot), Collections.emptyMap(), Collections.emptyMap());
        }
        List<Table> locked = operationMapper.lockTables(
                request.getShopId(), request.getSourceTable(), request.getTargetTable());
        Table source = findTable(locked, request.getSourceTable());
        Table target = findTable(locked, request.getTargetTable());
        Order order = operationMapper.lockOrder(request.getShopId(), request.getOrderNo());
        List<Order> sourceOrders = source == null ? Collections.emptyList()
                : operationMapper.lockUnsettledOrders(request.getShopId(), request.getSourceTable());
        List<Order> targetOrders = target == null ? Collections.emptyList()
                : operationMapper.lockUnsettledOrders(request.getShopId(), request.getTargetTable());
        List<Order> affected = new ArrayList<>(sourceOrders);
        affected.addAll(targetOrders);
        Map<String, Object> before = mergeState(source, target, sourceOrders, targetOrders);
        audit.setBefore_state(json(before));
        audit.setOrder_nos(json(orderNos(affected)));

        if (source == null || target == null || order == null) {
            return reject(audit, 404, "当前门店的订单、源桌或目标桌不存在", affected, before, before);
        }
        if (!"unsettled".equals(order.getTransac_status())
                || !request.getSourceTable().equals(order.getTable_number())) {
            return reject(audit, 409, "订单状态或所在桌台已变化，请刷新后重试", affected, before, before);
        }
        if (!Integer.valueOf(1).equals(source.getStatus())) {
            return reject(audit, 409, "源桌未开台，无法换台", affected, before, before);
        }
        if (Integer.valueOf(2).equals(target.getStatus())) {
            return reject(audit, 409, "目标桌已结账待清台，无法换台", affected, before, before);
        }
        if (operationMapper.moveOrder(order.getId(), request.getShopId(),
                request.getSourceTable(), request.getTargetTable()) != 1) {
            throw new IllegalStateException("订单状态已变化，换台已回滚，请重试");
        }

        List<Order> sourceRemaining = sourceOrders.stream()
                .filter(item -> !request.getOrderNo().equals(item.getOrder_no())).collect(Collectors.toList());
        List<Order> targetAfter = new ArrayList<>(targetOrders);
        order.setTable_number(request.getTargetTable());
        order.setMaster_order_no(null);
        targetAfter.add(order);
        Date now = new Date();
        int sourceStatus = sourceRemaining.isEmpty() ? 0 : 1;
        String sourcePointer = sourceRemaining.isEmpty() ? null : sourceRemaining.get(0).getOrder_no();
        Date sourceOut = sourceRemaining.isEmpty() ? now : null;
        if (operationMapper.updateTableState(source.getId(), request.getShopId(), sourceStatus, sourcePointer,
                outstandingAmount(sourceRemaining), source.getOpen_time(), sourceOut) != 1) {
            throw new IllegalStateException("源桌状态更新失败，换台已回滚");
        }
        if (sourceRemaining.isEmpty()) {
            operationMapper.finishSettledOrdersOnTable(request.getShopId(), request.getSourceTable(), now);
        }
        String targetPointer = containsOrderNo(targetOrders, target.getOrder_no())
                ? target.getOrder_no() : request.getOrderNo();
        Date targetOpen = target.getOpen_time() != null ? target.getOpen_time() : now;
        if (operationMapper.updateTableState(target.getId(), request.getShopId(), 1, targetPointer,
                outstandingAmount(targetAfter), targetOpen, null) != 1) {
            throw new IllegalStateException("目标桌状态更新失败，换台已回滚");
        }
        source.setStatus(sourceStatus);
        source.setOrder_no(sourcePointer);
        source.setOut_time(sourceOut);
        target.setStatus(1);
        target.setOrder_no(targetPointer);
        target.setOpen_time(targetOpen);
        if (projectionService != null && order.getId() != null) {
            projectionService.publishAfterCommit(order.getId(), "ORDER_UPDATED", null, null, null);
        }
        dispatchTableChangePrint(request.getShopId(), "换台", request.getSourceTable(), request.getTargetTable(),
                Collections.singletonList(request.getOrderNo()), request.getOperatorId());
        CashierTableOperationResult result = CashierTableOperationResult.success("换台成功", target);
        finishAudit(audit, result, mergeState(source, target, sourceRemaining, targetAfter));
        return result;
    }

    private CashierTableOperationResult reject(CashierTableAudit audit, int code, String message,
                                                List<Order> orders, Map<String, Object> before,
                                                Map<String, Object> after) {
        audit.setOrder_nos(json(orderNos(orders)));
        audit.setBefore_state(json(before));
        CashierTableOperationResult result = CashierTableOperationResult.rejected(code, message);
        finishAudit(audit, result, after);
        return result;
    }

    private void finishAudit(CashierTableAudit audit, CashierTableOperationResult result, Map<String, Object> after) {
        audit.setResult_status(result.isSuccess() ? "SUCCESS" : "REJECTED");
        audit.setResult_code(result.getCode());
        audit.setReason(result.getMessage());
        audit.setAfter_state(json(after));
        if (audit.getOrder_nos() == null) {
            audit.setOrder_nos("[]");
        }
        if (audit.getBefore_state() == null) {
            audit.setBefore_state("{}");
        }
    }

    private CashierTableAudit baseAudit(CashierTableOperationRequest request, String fingerprint) {
        CashierTableAudit audit = new CashierTableAudit();
        audit.setShop_id(request.getShopId());
        audit.setModule(MODULE);
        audit.setAction(request.getAction());
        audit.setTarget_id(auditText(request.getSourceTable(), 64));
        audit.setAdmin_id(request.getOperatorId());
        audit.setIp(auditText(request.getIp(), 64));
        audit.setSource_table(auditText(request.getSourceTable(), 50));
        audit.setTarget_table(auditText(request.getTargetTable(), 50));
        audit.setRequest_key(request.getRequestKey());
        audit.setRequest_fingerprint(fingerprint);
        audit.setTrace_id(auditText(request.getTraceId(), 128));
        Map<String, Object> snapshot = new LinkedHashMap<>();
        snapshot.put("sourceTable", auditText(request.getSourceTable(), 50));
        snapshot.put("targetTable", auditText(request.getTargetTable(), 50));
        snapshot.put("orderNo", auditText(request.getOrderNo(), 64));
        audit.setRequest_snapshot(json(snapshot));
        return audit;
    }

    private static Map<String, Object> state(Table table, List<Order> orders) {
        Map<String, Object> state = new LinkedHashMap<>();
        state.put("table", table == null ? null : table.getNumber());
        state.put("status", table == null ? null : table.getStatus());
        state.put("orderPointer", table == null ? null : table.getOrder_no());
        state.put("unsettledOrders", orderNos(orders));
        return state;
    }

    private static Map<String, Object> mergeState(Table source, Table target,
                                                   List<Order> sourceOrders, List<Order> targetOrders) {
        Map<String, Object> state = new LinkedHashMap<>();
        state.put("source", state(source, sourceOrders));
        state.put("target", state(target, targetOrders));
        return state;
    }

    private static List<String> orderNos(List<Order> orders) {
        return orders == null ? Collections.emptyList() : orders.stream()
                .map(Order::getOrder_no).filter(StringUtils::hasText).collect(Collectors.toList());
    }

    private static boolean containsOrderNo(List<Order> orders, String orderNo) {
        if (!StringUtils.hasText(orderNo) || orders == null) return false;
        for (Order order : orders) {
            if (order != null && orderNo.equals(order.getOrder_no())) return true;
        }
        return false;
    }

    private static Table findTable(List<Table> tables, String number) {
        if (tables == null) return null;
        for (Table table : tables) {
            if (number.equals(table.getNumber())) return table;
        }
        return null;
    }

    private static void normalize(CashierTableOperationRequest request) {
        if (request == null || request.getShopId() == null) {
            throw new IllegalArgumentException("缺少门店上下文");
        }
        request.setAction(trimUpper(request.getAction()));
        request.setSourceTable(trim(request.getSourceTable()));
        request.setTargetTable(trim(request.getTargetTable()));
        request.setOrderNo(trim(request.getOrderNo()));
        request.setRequestKey(trim(request.getRequestKey()));
        if (!StringUtils.hasText(request.getRequestKey())) {
            request.setRequestKey(StringUtils.hasText(request.getTraceId()) ? request.getTraceId() : java.util.UUID.randomUUID().toString());
        }
        if (request.getRequestKey().length() > 128) {
            request.setRequestKey("sha256:" + sha256(request.getRequestKey()));
        }
    }

    private static String fingerprint(CashierTableOperationRequest request) {
        String raw = "TRANSFER".equals(request.getAction())
                ? request.getAction() + "|" + request.getTargetTable() + "|" + request.getOrderNo()
                : request.getAction() + "|" + request.getSourceTable() + "|" + request.getTargetTable();
        try {
            byte[] digest = MessageDigest.getInstance("SHA-256").digest(raw.getBytes(StandardCharsets.UTF_8));
            StringBuilder value = new StringBuilder();
            for (byte b : digest) value.append(String.format("%02x", b));
            return value.toString();
        } catch (NoSuchAlgorithmException e) {
            throw new IllegalStateException("SHA-256 unavailable", e);
        }
    }

    private String json(Object value) {
        try {
            return objectMapper.writeValueAsString(value);
        } catch (JsonProcessingException e) {
            throw new IllegalStateException("审计数据序列化失败", e);
        }
    }

    private static String trim(String value) {
        return value == null ? null : value.trim();
    }

    private static String trimUpper(String value) {
        String text = trim(value);
        return text == null ? "" : text.toUpperCase(java.util.Locale.ROOT);
    }

    private static String auditText(String value, int maxLength) {
        if (value == null || value.length() <= maxLength) return value;
        return value.substring(0, maxLength);
    }

    private static double outstandingAmount(List<Order> orders) {
        double amount = 0d;
        if (orders != null) {
            for (Order order : orders) {
                if (order != null && "unsettled".equals(order.getTransac_status())) {
                    amount += OrderNetRevenue.netRevenueYuan(order);
                }
            }
        }
        return Math.round(Math.max(0d, amount) * 100d) / 100d;
    }

    private static String sha256(String value) {
        try {
            byte[] digest = MessageDigest.getInstance("SHA-256")
                    .digest(value.getBytes(StandardCharsets.UTF_8));
            StringBuilder result = new StringBuilder();
            for (byte b : digest) result.append(String.format("%02x", b));
            return result.toString();
        } catch (NoSuchAlgorithmException e) {
            throw new IllegalStateException("SHA-256 unavailable", e);
        }
    }

    private void dispatchTableChangePrint(Integer shopId, String operationType, String sourceTable,
                                          String targetTable, List<String> orderNos, Integer operatorId) {
        if (printDispatcherService == null || shopId == null) {
            return;
        }
        com.lanf.util.AfterCommitExecutor.execute("table_op_print:" + shopId + ":" + operationType + ":" + sourceTable + "->" + targetTable, () -> {
            try {
                String timeStr = java.time.LocalDateTime.now()
                        .format(java.time.format.DateTimeFormatter.ofPattern("yyyy-MM-dd HH:mm:ss"));
                StringBuilder sb = new StringBuilder();
                sb.append("<CB>【").append(operationType).append("通知】</CB><BR>");
                sb.append("--------------------------------<BR>");
                sb.append("<B>原桌号：</B><CB>").append(sourceTable != null ? sourceTable : "未知").append("</CB><BR>");
                sb.append("<B>新桌号：</B><CB>").append(targetTable != null ? targetTable : "未知").append("</CB><BR>");
                if (orderNos != null && !orderNos.isEmpty()) {
                    sb.append("关联订单：").append(String.join(",", orderNos)).append("<BR>");
                }
                sb.append("操作时间：").append(timeStr).append("<BR>");
                if (operatorId != null) {
                    sb.append("操作人员：ID ").append(operatorId).append("<BR>");
                }
                sb.append("--------------------------------<BR>");
                sb.append("<C>*** 请后厨与传菜员注意更新送餐桌号 ***</C><BR><BR><CUT>");

                String content = sb.toString();
                printDispatcherService.dispatchCustom(shopId, com.lanf.printing.model.PrintScenario.KITCHEN, content, operatorId);
                printDispatcherService.dispatchCustom(shopId, com.lanf.printing.model.PrintScenario.EXPEDITE, content, operatorId);
            } catch (Exception ex) {
                log.error("[table-op-print] 打印{}小票异常: shopId={}, source={}, target={}",
                        operationType, shopId, sourceTable, targetTable, ex);
            }
        });
    }

    @Transactional(rollbackFor = Exception.class, isolation = Isolation.READ_COMMITTED)
    public Map<String, Object> batchClear(Integer shopId, List<Table> tables,
                                          Integer operatorId, String operatorAccount, String traceId) {
        Date now = new Date();
        int successCount = 0;
        List<String> failedTableNumbers = new ArrayList<>();
        if (tables != null) {
            for (Table t : tables) {
                if (t == null || t.getNumber() == null) continue;
                String tableNumber = t.getNumber().trim();
                List<Order> unsettled = operationMapper.lockUnsettledOrders(shopId, tableNumber);
                if (unsettled != null && !unsettled.isEmpty()) {
                    failedTableNumbers.add(tableNumber);
                    continue;
                }
                Table locked = operationMapper.lockTable(shopId, tableNumber);
                if (locked == null) {
                    failedTableNumbers.add(tableNumber);
                    continue;
                }
                if (Integer.valueOf(0).equals(locked.getStatus())) {
                    successCount++;
                    continue;
                }
                if (!Integer.valueOf(1).equals(locked.getStatus()) && !Integer.valueOf(2).equals(locked.getStatus())) {
                    failedTableNumbers.add(tableNumber);
                    continue;
                }
                int expectedStatus = locked.getStatus();
                int affected = operationMapper.clearTable(locked.getId(), shopId, expectedStatus, now);
                if (affected == 1) {
                    operationMapper.finishSettledOrdersOnTable(shopId, tableNumber, now);
                    try {
                        CashierTableAudit audit = new CashierTableAudit();
                        audit.setShop_id(shopId);
                        audit.setModule(MODULE);
                        audit.setAction("BATCH_CLEAR");
                        audit.setTarget_id(auditText(tableNumber, 64));
                        audit.setAdmin_id(operatorId);
                        audit.setSource_table(auditText(tableNumber, 50));
                        audit.setRequest_key(traceId != null ? traceId : java.util.UUID.randomUUID().toString());
                        audit.setResult_status("SUCCESS");
                        audit.setResult_code(200);
                        audit.setReason("批量清台成功");
                        audit.setCreated_at(now);
                        audit.setBefore_state(json(state(locked, Collections.emptyList())));
                        locked.setStatus(0);
                        locked.setOut_time(now);
                        locked.setOrder_no(null);
                        locked.setAmount(0D);
                        audit.setAfter_state(json(state(locked, Collections.emptyList())));
                        auditMapper.insert(audit);
                    } catch (Exception ex) {
                        log.warn("batchClear audit insertion failed: table={}, error={}", tableNumber, ex.getMessage());
                    }
                    successCount++;
                } else {
                    failedTableNumbers.add(tableNumber);
                }
            }
        }
        Map<String, Object> data = new LinkedHashMap<>();
        data.put("success_count", successCount);
        data.put("failed_table_numbers", failedTableNumbers);
        return data;
    }
}
