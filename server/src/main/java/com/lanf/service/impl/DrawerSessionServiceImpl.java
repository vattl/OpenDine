package com.lanf.service.impl;

import com.baomidou.mybatisplus.core.conditions.query.QueryWrapper;
import com.baomidou.mybatisplus.extension.service.impl.ServiceImpl;
import com.lanf.entity.CashMovement;
import com.lanf.entity.DrawerSession;
import com.lanf.entity.Order;
import com.lanf.entity.OrderDetail;
import com.lanf.entity.PaymentLedger;
import com.lanf.entity.Shift;
import com.lanf.entity.Admin;
import com.lanf.common.ApiException;
import com.lanf.mapper.CashMovementMapper;
import com.lanf.mapper.DrawerSessionMapper;
import com.lanf.service.DrawerSessionService;
import com.lanf.service.IShiftService;
import com.lanf.service.IAdminService;
import com.lanf.service.IOrderService;
import com.lanf.service.IOrderDetailService;
import com.lanf.service.IMemberRechargeService;
import com.lanf.service.MemberRechargeSummary;
import com.lanf.service.PaymentLedgerService;
import com.lanf.payment.support.PaymentChannelCatalog;
import com.lanf.util.AdminNameResolver;
import org.springframework.beans.factory.annotation.Autowired;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.util.StringUtils;

import java.math.BigDecimal;
import java.time.LocalDate;
import java.util.ArrayList;
import java.util.Collections;
import java.util.Date;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Objects;
import java.util.UUID;
import java.security.MessageDigest;
import java.nio.charset.StandardCharsets;

@Service
public class DrawerSessionServiceImpl extends ServiceImpl<DrawerSessionMapper, DrawerSession> implements DrawerSessionService {

    private static final Logger log = LoggerFactory.getLogger(DrawerSessionServiceImpl.class);
    private static final String DEFAULT_TERMINAL = "POS-01";
    private static final String DEFAULT_DRAWER = "DEFAULT";

    @Autowired
    private CashMovementMapper cashMovementMapper;

    @Autowired(required = false)
    private IShiftService shiftService;

    @Autowired(required = false)
    private PaymentLedgerService paymentLedgerService;

    @Autowired(required = false)
    private IAdminService adminService;

    @Autowired(required = false)
    private IOrderService orderService;

    @Autowired(required = false)
    private IMemberRechargeService memberRechargeService;

    @Autowired(required = false)
    private IOrderDetailService orderDetailService;

    @Override
    @Transactional(rollbackFor = Exception.class)
    public DrawerSession openSession(
            Integer shopId,
            String terminalId,
            String drawerCode,
            Integer adminId,
            int openingFloatFen,
            String businessDay,
            String requestId) {

        if (shopId == null || shopId <= 0) {
            throw new IllegalArgumentException("门店ID不能为空");
        }
        if (adminId == null || adminId <= 0) {
            throw new IllegalArgumentException("开班操作人不能为空");
        }
        if (openingFloatFen < 0) {
            throw new IllegalArgumentException("备用金金额不能为负数");
        }

        String termId = StringUtils.hasText(terminalId) ? terminalId.trim() : DEFAULT_TERMINAL;
        String dCode = StringUtils.hasText(drawerCode) ? drawerCode.trim() : DEFAULT_DRAWER;
        String bDay = StringUtils.hasText(businessDay) ? businessDay.trim()
                : LocalDate.now(java.time.ZoneId.of("Asia/Shanghai")).toString();
        String reqId = StringUtils.hasText(requestId) ? requestId.trim() : "OPEN_" + UUID.randomUUID().toString().replace("-", "");

        // 幂等防重检查
        DrawerSession existing = getOne(new QueryWrapper<DrawerSession>()
                .eq("shop_id", shopId)
                .eq("request_id", reqId)
                .last("LIMIT 1"));
        if (existing != null) {
            log.info("drawer open idempotency hit shop={} requestId={} session={}", shopId, reqId, existing.getId());
            return existing;
        }

        // 单活动钱箱检查：同一 (shop_id, terminal_id, drawer_code) 只能存在一个 OPEN/CLOSING 会话
        DrawerSession active = getActiveSession(shopId, termId, dCode);
        if (active != null) {
            throw new IllegalStateException("当前终端已存在未关闭的钱箱会话(" + active.getSession_no() + ")，请先交班关箱");
        }

        String sessionNo = "DS_" + shopId + "_" + termId + "_" + System.currentTimeMillis();
        DrawerSession session = DrawerSession.builder()
                .session_no(sessionNo)
                .shop_id(shopId)
                .terminal_id(termId)
                .drawer_code(dCode)
                .state(DrawerSession.STATE_OPEN)
                .opened_by(adminId)
                .opened_at(new Date())
                .opening_float_fen(openingFloatFen)
                .expected_cash_fen(openingFloatFen)
                .business_day(bDay)
                .request_id(reqId)
                .version(1)
                .created_at(new Date())
                .updated_at(new Date())
                .build();

        save(session);

        // 写入 OPENING_FLOAT 初始现金动作
        String movementNo = "CM_" + shopId + "_" + System.currentTimeMillis() + "_0";
        CashMovement floatMovement = CashMovement.builder()
                .movement_no(movementNo)
                .drawer_session_id(session.getId())
                .shop_id(shopId)
                .movement_type(CashMovement.TYPE_OPENING_FLOAT)
                .amount_fen(openingFloatFen)
                .current_balance_fen(openingFloatFen)
                .reason_code("INITIAL_FLOAT")
                .remark("开班备用金录入")
                .operator_id(adminId)
                .request_id(reqId)
                .occurred_at(new Date())
                .created_at(new Date())
                .build();

        cashMovementMapper.insert(floatMovement);

        // 同步关联 t_shift 班次
        if (shiftService != null) {
            Shift openShift = shiftService.getOne(new QueryWrapper<Shift>()
                    .eq("admin_id", adminId)
                    .eq("shop_id", shopId)
                    .isNull("end_time")
                    .last("LIMIT 1"));
            if (openShift != null) {
                openShift.setDrawer_session_id(session.getId());
                openShift.setTerminal_id(termId);
                openShift.setBusiness_day(bDay);
                shiftService.updateById(openShift);
            } else {
                Shift newShift = new Shift();
                newShift.setAdmin_id(adminId);
                newShift.setShop_id(shopId);
                newShift.setStart_time(session.getOpened_at());
                newShift.setStart_cash(BigDecimal.valueOf(openingFloatFen, 2));
                newShift.setOrder_count(0);
                newShift.setTotal_amount(BigDecimal.ZERO);
                newShift.setDrawer_session_id(session.getId());
                newShift.setTerminal_id(termId);
                newShift.setState("OPEN");
                newShift.setBusiness_day(bDay);
                newShift.setCreated_at(new Date());
                shiftService.save(newShift);
            }
        }

        return session;
    }

    @Override
    public DrawerSession getActiveSession(Integer shopId, String terminalId, String drawerCode) {
        String termId = StringUtils.hasText(terminalId) ? terminalId.trim() : DEFAULT_TERMINAL;
        String dCode = StringUtils.hasText(drawerCode) ? drawerCode.trim() : DEFAULT_DRAWER;
        return getOne(new QueryWrapper<DrawerSession>()
                .eq("shop_id", shopId)
                .eq("terminal_id", termId)
                .eq("drawer_code", dCode)
                .in("state", DrawerSession.STATE_OPEN, DrawerSession.STATE_CLOSING)
                .orderByDesc("id")
                .last("LIMIT 1"));
    }

    @Override
    public int calculateExpectedCashFen(Long drawerSessionId) {
        if (drawerSessionId == null) {
            return 0;
        }
        List<CashMovement> movements = cashMovementMapper.selectList(new QueryWrapper<CashMovement>()
                .eq("drawer_session_id", drawerSessionId)
                .notIn("movement_type", CashMovement.TYPE_COUNT, CashMovement.TYPE_NO_SALE));

        int expected = 0;
        for (CashMovement m : movements) {
            if (m.getAmount_fen() != null) {
                expected += m.getAmount_fen();
            }
        }
        return expected;
    }

    @Override
    public int getCurrentCashBalanceFen(Long drawerSessionId) {
        if (drawerSessionId == null) {
            return 0;
        }
        CashMovement last = cashMovementMapper.selectOne(new QueryWrapper<CashMovement>()
                .eq("drawer_session_id", drawerSessionId)
                .orderByDesc("id")
                .last("LIMIT 1"));
        return last != null && last.getCurrent_balance_fen() != null ? last.getCurrent_balance_fen() : 0;
    }

    @Override
    @Transactional(rollbackFor = Exception.class)
    public CashMovement recordCashSale(
            Integer shopId,
            String terminalId,
            String drawerCode,
            Order order,
            PaymentLedger ledger,
            int cashFen,
            Integer operatorId) {

        if (cashFen <= 0) {
            return null;
        }
        DrawerSession session = getActiveSession(shopId, terminalId, drawerCode);
        if (session == null) {
            // 兼容性保护：若未开箱则尝试获取该门店任意活动钱箱
            session = getOne(new QueryWrapper<DrawerSession>()
                    .eq("shop_id", shopId)
                    .in("state", DrawerSession.STATE_OPEN, DrawerSession.STATE_CLOSING)
                    .orderByDesc("id")
                    .last("LIMIT 1"));
        }
        if (session == null) {
            return null;
        }

        int currentBalance = getCurrentCashBalanceFen(session.getId());
        int newBalance = currentBalance + cashFen;
        String movementNo = "CM_" + shopId + "_" + System.currentTimeMillis() + "_" + (order != null ? order.getOrder_no() : "CASH");

        CashMovement movement = CashMovement.builder()
                .movement_no(movementNo)
                .drawer_session_id(session.getId())
                .shop_id(shopId)
                .movement_type(CashMovement.TYPE_CASH_SALE)
                .amount_fen(cashFen)
                .current_balance_fen(newBalance)
                .reason_code("CASH_CHECKOUT")
                .remark("订单现金结算: " + (order != null ? order.getOrder_no() : ""))
                .operator_id(operatorId != null ? operatorId : session.getOpened_by())
                .order_id(order != null && order.getId() != null ? order.getId().longValue() : null)
                .order_no(order != null ? order.getOrder_no() : null)
                .payment_ledger_id(ledger != null ? ledger.getId() : null)
                .request_id(ledger != null ? ledger.getRequest_id() : null)
                .occurred_at(new Date())
                .created_at(new Date())
                .build();

        cashMovementMapper.insert(movement);
        return movement;
    }

    @Override
    @Transactional(rollbackFor = Exception.class)
    public CashMovement recordCashRefund(
            Integer shopId,
            String terminalId,
            String drawerCode,
            Order order,
            PaymentLedger originalLedger,
            int refundFen,
            Integer operatorId,
            String reason) {

        if (refundFen <= 0) {
            return null;
        }
        DrawerSession session = getActiveSession(shopId, terminalId, drawerCode);
        if (session == null) {
            session = getOne(new QueryWrapper<DrawerSession>()
                    .eq("shop_id", shopId)
                    .in("state", DrawerSession.STATE_OPEN, DrawerSession.STATE_CLOSING)
                    .orderByDesc("id")
                    .last("LIMIT 1"));
        }
        if (session == null) {
            return null;
        }

        int currentBalance = getCurrentCashBalanceFen(session.getId());
        int delta = -Math.abs(refundFen);
        int newBalance = currentBalance + delta;
        String movementNo = "CM_REF_" + shopId + "_" + System.currentTimeMillis();

        CashMovement movement = CashMovement.builder()
                .movement_no(movementNo)
                .drawer_session_id(session.getId())
                .shop_id(shopId)
                .movement_type(CashMovement.TYPE_CASH_REFUND)
                .amount_fen(delta)
                .current_balance_fen(newBalance)
                .reason_code("CASH_REFUND")
                .remark(StringUtils.hasText(reason) ? reason : "现金退款/反结账现金冲正")
                .operator_id(operatorId != null ? operatorId : session.getOpened_by())
                .order_id(order != null && order.getId() != null ? order.getId().longValue() : null)
                .order_no(order != null ? order.getOrder_no() : null)
                .payment_ledger_id(originalLedger != null ? originalLedger.getId() : null)
                .occurred_at(new Date())
                .created_at(new Date())
                .build();

        cashMovementMapper.insert(movement);
        return movement;
    }

    @Override
    @Transactional(rollbackFor = Exception.class)
    public CashMovement recordManualMovement(
            Integer shopId,
            Long drawerSessionId,
            String movementType,
            int amountFen,
            String reasonCode,
            String remark,
            Integer operatorId,
            Integer approverId,
            String requestId) {

        if (drawerSessionId == null) {
            throw new IllegalArgumentException("钱箱会话ID不能为空");
        }
        DrawerSession session = getById(drawerSessionId);
        if (session == null) {
            throw new IllegalArgumentException("钱箱会话不存在");
        }
        if (!Objects.equals(shopId, session.getShop_id())) {
            throw new ApiException(403, "SHIFT_SHOP_MISMATCH", "钱箱会话不属于当前门店");
        }
        if (!DrawerSession.STATE_OPEN.equals(session.getState()) && !DrawerSession.STATE_CLOSING.equals(session.getState())) {
            throw new IllegalStateException("钱箱会话已关闭，不可执行现金动作");
        }

        String reqId = StringUtils.hasText(requestId) ? requestId.trim() : null;
        if (reqId != null) {
            CashMovement existing = cashMovementMapper.selectOne(new QueryWrapper<CashMovement>()
                    .eq("shop_id", shopId)
                    .eq("request_id", reqId)
                    .last("LIMIT 1"));
            if (existing != null) {
                log.info("cash movement idempotency hit shop={} requestId={} movement={}",
                        shopId, reqId, existing.getId());
                return existing;
            }
        }

        int currentBalance = getCurrentCashBalanceFen(drawerSessionId);
        int delta = 0;
        int absAmount = Math.abs(amountFen);

        switch (movementType) {
            case CashMovement.TYPE_CASH_IN:
                delta = absAmount;
                break;
            case CashMovement.TYPE_CASH_OUT:
            case CashMovement.TYPE_CASH_DROP:
                if (currentBalance < absAmount && approverId == null) {
                    throw new IllegalStateException("钱箱现金不足，当前余额 " + (currentBalance / 100.0) + " 元，支取金额 " + (absAmount / 100.0) + " 元，超额支取须主管授权");
                }
                delta = -absAmount;
                break;
            case CashMovement.TYPE_NO_SALE:
                delta = 0;
                break;
            case CashMovement.TYPE_ADJUSTMENT:
                delta = amountFen;
                break;
            default:
                throw new IllegalArgumentException("不支持的现金动作类型: " + movementType);
        }

        int newBalance = currentBalance + delta;
        String movementNo = "CM_" + movementType + "_" + System.currentTimeMillis();

        CashMovement movement = CashMovement.builder()
                .movement_no(movementNo)
                .drawer_session_id(drawerSessionId)
                .shop_id(shopId)
                .movement_type(movementType)
                .amount_fen(delta)
                .current_balance_fen(newBalance)
                .reason_code(reasonCode)
                .remark(remark)
                .operator_id(operatorId)
                .approver_id(approverId)
                .request_id(reqId)
                .occurred_at(new Date())
                .created_at(new Date())
                .build();

        cashMovementMapper.insert(movement);
        return movement;
    }

    @Override
    @Transactional(rollbackFor = Exception.class)
    public DrawerSession closeSession(
            Integer shopId,
            Long drawerSessionId,
            Integer closedBy,
            int countedCashFen,
            String varianceReasonCode,
            String varianceNote,
            Integer approvedBy,
            String closeRequestId) {

        if (drawerSessionId == null) {
            throw new IllegalArgumentException("钱箱会话ID不能为空");
        }
        DrawerSession session = getById(drawerSessionId);
        if (session == null) {
            throw new IllegalArgumentException("钱箱会话不存在");
        }
        if (!Objects.equals(shopId, session.getShop_id())) {
            throw new ApiException(403, "SHIFT_SHOP_MISMATCH", "钱箱会话不属于当前门店");
        }
        if (DrawerSession.STATE_CLOSED.equals(session.getState())) {
            if (StringUtils.hasText(closeRequestId)
                    && closeRequestId.equals(session.getClose_request_id())) {
                log.info("drawer close idempotency hit shop={} requestId={} session={}",
                        shopId, closeRequestId, session.getId());
                return session;
            }
            throw new ApiException(409, "SHIFT_ALREADY_CLOSED", "该班次已完成交班");
        }

        int expectedCashFen = calculateExpectedCashFen(drawerSessionId);
        int varianceFen = countedCashFen - expectedCashFen;
        log.info("drawer close variance shop={} session={} varianceFen={} approvalRequired={} approved={}",
                shopId, drawerSessionId, varianceFen, Math.abs(varianceFen) > 5000, approvedBy != null);

        // 差额审批规则：差额绝对值大于 50 元(5000分)且未审批时抛出异常阻断
        if (Math.abs(varianceFen) > 5000 && approvedBy == null) {
            throw new IllegalStateException("盘点存在长短款差额 " + (varianceFen / 100.0) + " 元，超过 50 元须店长二次授权核验");
        }

        session.setState(DrawerSession.STATE_CLOSED);
        session.setExpected_cash_fen(expectedCashFen);
        session.setCounted_cash_fen(countedCashFen);
        session.setVariance_fen(varianceFen);
        session.setClosed_by(closedBy);
        session.setClosed_at(new Date());
        session.setVariance_reason_code(varianceReasonCode);
        session.setVariance_note(varianceNote);
        session.setApproved_by(approvedBy);
        session.setApproved_at(approvedBy != null ? new Date() : null);
        session.setClose_request_id(closeRequestId);
        session.setVersion(session.getVersion() != null ? session.getVersion() + 1 : 2);
        session.setUpdated_at(new Date());

        updateById(session);

        // 写入 COUNT 盘点动作快照
        CashMovement countMovement = CashMovement.builder()
                .movement_no("CM_COUNT_" + System.currentTimeMillis())
                .drawer_session_id(drawerSessionId)
                .shop_id(shopId)
                .movement_type(CashMovement.TYPE_COUNT)
                .amount_fen(0)
                .current_balance_fen(countedCashFen)
                .reason_code("SHIFT_HANDOVER")
                .remark("交班盲盘现金实盘: " + (countedCashFen / 100.0) + " 元, 应有: " + (expectedCashFen / 100.0) + " 元")
                .operator_id(closedBy)
                .approver_id(approvedBy)
                .request_id(closeRequestId)
                .occurred_at(new Date())
                .created_at(new Date())
                .build();
        cashMovementMapper.insert(countMovement);

        // 若存在长短款差额，自动补记一条 ADJUSTMENT 平账记录
        if (varianceFen != 0) {
            CashMovement adjMovement = CashMovement.builder()
                    .movement_no("CM_ADJ_" + System.currentTimeMillis())
                    .drawer_session_id(drawerSessionId)
                    .shop_id(shopId)
                    .movement_type(CashMovement.TYPE_ADJUSTMENT)
                    .amount_fen(varianceFen)
                    .current_balance_fen(countedCashFen)
                    .reason_code(varianceReasonCode != null ? varianceReasonCode : "VARIANCE_ADJUSTMENT")
                    .remark("盘点差额平账调整: " + (varianceFen > 0 ? "长款+" : "短款") + (varianceFen / 100.0) + " 元")
                    .operator_id(closedBy)
                    .approver_id(approvedBy)
                    .occurred_at(new Date())
                    .created_at(new Date())
                    .build();
            cashMovementMapper.insert(adjMovement);
        }

        // 同步关闭对应 t_shift
        if (shiftService != null) {
            Shift shift = shiftService.getOne(new QueryWrapper<Shift>()
                    .eq("drawer_session_id", drawerSessionId)
                    .isNull("end_time")
                    .last("LIMIT 1"));
            if (shift == null) {
                shift = shiftService.getOne(new QueryWrapper<Shift>()
                        .eq("admin_id", closedBy)
                        .eq("shop_id", shopId)
                        .isNull("end_time")
                        .last("LIMIT 1"));
            }
            if (shift != null) {
                shift.setState("CLOSED");
                shift.setEnd_time(session.getClosed_at());
                shift.setEnd_cash(BigDecimal.valueOf(countedCashFen, 2));
                shiftService.updateById(shift);
            }
        }

        return session;
    }

    @Override
    public List<CashMovement> listMovements(Long drawerSessionId) {
        if (drawerSessionId == null) {
            return Collections.emptyList();
        }
        return cashMovementMapper.selectList(new QueryWrapper<CashMovement>()
                .eq("drawer_session_id", drawerSessionId)
                .orderByAsc("id"));
    }

    @Override
    public Map<String, Object> getShiftSummaryReport(Long drawerSessionId) {
        DrawerSession session = getById(drawerSessionId);
        if (session == null) {
            return Collections.emptyMap();
        }
        if (!DrawerSession.STATE_CLOSED.equals(session.getState())) {
            throw new ApiException(409, "SHIFT_NOT_CLOSED", "班次尚未完成盲盘交班，不可查看对账报告");
        }

        Map<String, Object> report = new LinkedHashMap<>();
        report.put("session_id", session.getId());
        report.put("session_no", session.getSession_no());
        report.put("shop_id", session.getShop_id());
        report.put("terminal_id", session.getTerminal_id());
        report.put("drawer_code", session.getDrawer_code());
        report.put("state", session.getState());
        report.put("business_day", session.getBusiness_day());
        report.put("opened_by", session.getOpened_by());
        report.put("opened_by_name", adminName(session.getOpened_by()));
        report.put("opened_at", session.getOpened_at());
        report.put("closed_by", session.getClosed_by());
        report.put("closed_by_name", adminName(session.getClosed_by()));
        report.put("closed_at", session.getClosed_at());
        report.put("approved_by", session.getApproved_by());
        report.put("operator_name", adminName(session.getOpened_by()));
        report.put("terminal_name", session.getTerminal_id());
        report.put("drawer_name", session.getDrawer_code());
        long durationSeconds = session.getOpened_at() != null && session.getClosed_at() != null
                ? Math.max(0L, (session.getClosed_at().getTime() - session.getOpened_at().getTime()) / 1000L) : 0L;
        report.put("duration_seconds", durationSeconds);
        report.put("approval_status", session.getApproved_by() != null ? "APPROVED"
                : (session.getVariance_fen() != null && session.getVariance_fen() != 0 ? "NOT_REQUIRED" : "NOT_REQUIRED"));
        report.put("approved_by_name", adminName(session.getApproved_by()));
        report.put("approved_at", session.getApproved_at());

        // 现金账本流转明细
        List<CashMovement> movements = listMovements(drawerSessionId);
        int openingFloatFen = session.getOpening_float_fen() != null ? session.getOpening_float_fen() : 0;
        int cashSaleFen = 0;
        int cashRefundFen = 0;
        int cashInFen = 0;
        int cashOutFen = 0;
        int cashDropFen = 0;

        for (CashMovement m : movements) {
            if (CashMovement.TYPE_CASH_SALE.equals(m.getMovement_type())) {
                cashSaleFen += m.getAmount_fen() != null ? m.getAmount_fen() : 0;
            } else if (CashMovement.TYPE_CASH_REFUND.equals(m.getMovement_type())) {
                cashRefundFen += Math.abs(m.getAmount_fen() != null ? m.getAmount_fen() : 0);
            } else if (CashMovement.TYPE_CASH_IN.equals(m.getMovement_type())) {
                cashInFen += m.getAmount_fen() != null ? m.getAmount_fen() : 0;
            } else if (CashMovement.TYPE_CASH_OUT.equals(m.getMovement_type())) {
                cashOutFen += Math.abs(m.getAmount_fen() != null ? m.getAmount_fen() : 0);
            } else if (CashMovement.TYPE_CASH_DROP.equals(m.getMovement_type())) {
                cashDropFen += Math.abs(m.getAmount_fen() != null ? m.getAmount_fen() : 0);
            }
        }

        int expectedCashFen = session.getExpected_cash_fen() != null
                ? session.getExpected_cash_fen()
                : calculateExpectedCashFen(drawerSessionId);
        int countedCashFen = session.getCounted_cash_fen() != null
                ? session.getCounted_cash_fen()
                : getCurrentCashBalanceFen(drawerSessionId);
        int varianceFen = session.getVariance_fen() != null
                ? session.getVariance_fen()
                : (countedCashFen - expectedCashFen);

        Map<String, Object> cashReport = new LinkedHashMap<>();
        cashReport.put("opening_float_yuan", fenToYuan(openingFloatFen));
        cashReport.put("opening_float_fen", openingFloatFen);
        cashReport.put("cash_sale_yuan", fenToYuan(cashSaleFen));
        cashReport.put("cash_refund_yuan", fenToYuan(cashRefundFen));
        cashReport.put("cash_in_yuan", fenToYuan(cashInFen));
        cashReport.put("cash_out_yuan", fenToYuan(cashOutFen));
        cashReport.put("cash_drop_yuan", fenToYuan(cashDropFen));
        cashReport.put("expected_cash_yuan", fenToYuan(expectedCashFen));
        cashReport.put("expected_cash_fen", expectedCashFen);
        cashReport.put("counted_cash_yuan", fenToYuan(countedCashFen));
        cashReport.put("counted_cash_fen", countedCashFen);
        cashReport.put("variance_yuan", fenToYuan(varianceFen));
        cashReport.put("variance_fen", varianceFen);
        cashReport.put("variance_reason_code", session.getVariance_reason_code());
        cashReport.put("variance_note", session.getVariance_note());
        report.put("cash_summary", cashReport);

        // 多渠道实收统计 (从不可变支付账本获取)
        Map<String, Object> channelSummary = new LinkedHashMap<>();
        List<Map<String, Object>> channelRows = new ArrayList<>();
        List<PaymentLedger> ledgers = Collections.emptyList();
        if (paymentLedgerService != null) {
            ledgers = paymentLedgerService.list(new QueryWrapper<PaymentLedger>()
                    .eq("drawer_session_id", drawerSessionId)
                    .eq("status", PaymentLedger.STATUS_SUCCEEDED));
            Map<String, String> paymentMethodByOrderNo = loadPaymentMethods(ledgers, session.getShop_id());

            Map<String, Integer> channelFen = new LinkedHashMap<>();
            int totalNetFen = 0;
            java.util.Set<String> orderSet = new java.util.HashSet<>();

            for (PaymentLedger pl : ledgers) {
                String ch = PaymentChannelCatalog.reportingCode(
                        pl.getChannel(), paymentMethodByOrderNo.get(pl.getOrder_no()));
                int amt = pl.getAmount_fen() != null ? pl.getAmount_fen() : 0;
                channelFen.put(ch, channelFen.getOrDefault(ch, 0) + amt);
                totalNetFen += amt;
                if (pl.getOrder_no() != null) {
                    orderSet.add(pl.getOrder_no());
                }
            }

            Map<String, Double> channelYuan = new LinkedHashMap<>();
            for (Map.Entry<String, Integer> e : channelFen.entrySet()) {
                channelYuan.put(e.getKey(), fenToYuan(e.getValue()));
            }
            channelSummary.put("by_channel", channelYuan);
            channelSummary.put("total_net_yuan", fenToYuan(totalNetFen));
            channelSummary.put("distinct_orders_count", orderSet.size());

            Map<String, Map<String, Object>> rowsByChannel = new LinkedHashMap<>();
            for (PaymentLedger pl : ledgers) {
                String channel = PaymentChannelCatalog.reportingCode(
                        pl.getChannel(), paymentMethodByOrderNo.get(pl.getOrder_no()));
                Map<String, Object> row = rowsByChannel.computeIfAbsent(channel, ignored -> {
                    Map<String, Object> created = new LinkedHashMap<>();
                    created.put("code", channel);
                    created.put("label", PaymentChannelCatalog.reportingLabel(channel));
                    created.put("transaction_count", 0);
                    created.put("refund_count", 0);
                    created.put("refund_amount_fen", 0L);
                    created.put("net_amount_fen", 0L);
                    return created;
                });
                int amount = pl.getAmount_fen() != null ? pl.getAmount_fen() : 0;
                if (PaymentLedger.ENTRY_TYPE_REFUND.equals(pl.getEntry_type())
                        || PaymentLedger.ENTRY_TYPE_REVERSAL.equals(pl.getEntry_type())) {
                    row.put("refund_count", ((Integer) row.get("refund_count")) + 1);
                    row.put("refund_amount_fen", ((Long) row.get("refund_amount_fen")) + Math.abs((long) amount));
                } else {
                    row.put("transaction_count", ((Integer) row.get("transaction_count")) + 1);
                }
                row.put("net_amount_fen", ((Long) row.get("net_amount_fen")) + amount);
            }
            channelRows.addAll(rowsByChannel.values());
        }
        report.put("channel_summary", channelSummary);
        report.put("channels", channelRows);

        MemberRechargeSummary rechargeSummary = memberRechargeService != null
                ? memberRechargeService.summarizeSuccessfulByDrawerSession(drawerSessionId)
                : null;
        if (rechargeSummary == null) rechargeSummary = MemberRechargeSummary.empty();
        report.put("member_recharge_summary", rechargeSummary.toMap());
        long orderCollectionsFen = 0L;
        for (Map<String, Object> channelRow : channelRows) {
            Object value = channelRow.get("net_amount_fen");
            if (value instanceof Number) orderCollectionsFen += ((Number) value).longValue();
        }
        report.put("total_collections_fen", orderCollectionsFen + rechargeSummary.getPrincipalFen());

        appendTransactionDetails(report, ledgers, session, drawerSessionId);

        List<Map<String, Object>> auditEvents = new ArrayList<>();
        long maxMovementId = 0L;
        for (CashMovement movement : movements) {
            Map<String, Object> event = new LinkedHashMap<>();
            event.put("event_id", movement.getId());
            event.put("event_type", movement.getMovement_type());
            event.put("amount_fen", movement.getAmount_fen());
            event.put("occurred_at", movement.getOccurred_at());
            event.put("operator_id", movement.getOperator_id());
            event.put("operator_name", adminName(movement.getOperator_id()));
            event.put("reference_no", movement.getMovement_no());
            auditEvents.add(event);
            if (movement.getId() != null) maxMovementId = Math.max(maxMovementId, movement.getId());
        }
        report.put("audit_events", auditEvents);

        long maxLedgerId = 0L;
        for (PaymentLedger ledger : ledgers) {
            if (ledger.getId() != null) maxLedgerId = Math.max(maxLedgerId, ledger.getId());
        }
        Map<String, Object> sourceWatermarks = new LinkedHashMap<>();
        sourceWatermarks.put("payment_ledger_id", maxLedgerId);
        sourceWatermarks.put("cash_event_id", maxMovementId);
        sourceWatermarks.put("session_version", session.getVersion() != null ? session.getVersion() : 0);
        Map<String, Object> integrity = new LinkedHashMap<>();
        integrity.put("version", session.getVersion() != null ? session.getVersion() : 0);
        integrity.put("status", "VERIFIED");
        integrity.put("source_watermarks", sourceWatermarks);
        integrity.put("report_hash", sha256(session.getSession_no() + "|" + expectedCashFen + "|"
                + countedCashFen + "|" + varianceFen + "|" + maxLedgerId + "|" + maxMovementId));
        report.put("integrity", integrity);

        return report;
    }

    @Override
    public Map<String, Object> getWorkbench(Integer shopId, Integer adminId) {
        DrawerSession active = getOne(new QueryWrapper<DrawerSession>()
                .eq("shop_id", shopId)
                .in("state", DrawerSession.STATE_OPEN, DrawerSession.STATE_CLOSING)
                .orderByDesc("id").last("LIMIT 1"), false);
        String businessDay = active != null && StringUtils.hasText(active.getBusiness_day())
                ? active.getBusiness_day() : LocalDate.now(java.time.ZoneId.of("Asia/Shanghai")).toString();

        Map<String, Object> result = new LinkedHashMap<>();
        result.put("business_day", businessDay);
        result.put("operator", identity(adminId, adminName(adminId)));
        result.put("terminal", active != null ? identity(active.getTerminal_id(), active.getTerminal_id()) : null);
        result.put("drawer", active != null ? drawerIdentity(active) : null);
        if (active != null) {
            Map<String, Object> currentShift = safeCurrentShift(active);
            MemberRechargeSummary rechargeSummary = memberRechargeService != null
                    ? memberRechargeService.summarizeSuccessfulByDrawerSession(active.getId())
                    : null;
            currentShift.put("member_recharge_summary",
                    (rechargeSummary != null ? rechargeSummary : MemberRechargeSummary.empty()).toMap());
            result.put("current_shift", currentShift);
        } else {
            result.put("current_shift", null);
        }

        CashMovement latest = cashMovementMapper.selectOne(new QueryWrapper<CashMovement>()
                .eq("shop_id", shopId)
                .eq(active != null, "drawer_session_id", active != null ? active.getId() : null)
                .orderByDesc("id").last("LIMIT 1"));
        result.put("latest_cash_movement", latest != null ? safeLatestMovement(latest, active == null) : null);

        DrawerSession previous = getOne(new QueryWrapper<DrawerSession>()
                .eq("shop_id", shopId).eq("state", DrawerSession.STATE_CLOSED)
                .orderByDesc("closed_at").last("LIMIT 1"), false);
        if (previous != null) {
            Map<String, Object> previousMap = new LinkedHashMap<>();
            previousMap.put("session_id", previous.getId());
            previousMap.put("closed_at", previous.getClosed_at());
            previousMap.put("balanced", previous.getVariance_fen() != null && previous.getVariance_fen() == 0);
            result.put("previous_shift", previousMap);
        } else {
            result.put("previous_shift", null);
        }

        int openDrawers = count(new QueryWrapper<DrawerSession>().eq("shop_id", shopId)
                .in("state", DrawerSession.STATE_OPEN, DrawerSession.STATE_CLOSING));
        int unsettledOrders = orderService != null ? orderService.count(new QueryWrapper<Order>()
                .eq("shop_id", shopId).notIn("transac_status", "success", "refunded", "cancelled")) : 0;
        int pendingPayments = paymentLedgerService != null ? paymentLedgerService.count(new QueryWrapper<PaymentLedger>()
                .eq("shop_id", shopId).eq("status", PaymentLedger.STATUS_PENDING)) : 0;
        int unapproved = count(new QueryWrapper<DrawerSession>().eq("shop_id", shopId)
                .eq("business_day", businessDay).eq("state", DrawerSession.STATE_CLOSED)
                .isNull("approved_by").and(w -> w.gt("variance_fen", 5000).or().lt("variance_fen", -5000)));
        Map<String, Object> readiness = new LinkedHashMap<>();
        readiness.put("open_drawer_count", openDrawers);
        readiness.put("unsettled_order_count", unsettledOrders);
        readiness.put("pending_payment_count", pendingPayments);
        readiness.put("unapproved_variance_count", unapproved);
        result.put("close_readiness", readiness);
        return result;
    }

    @Override
    public Map<String, Object> listShiftReports(Integer shopId, Long cursor, Integer limit) {
        int pageSize = clampLimit(limit);
        QueryWrapper<DrawerSession> query = new QueryWrapper<DrawerSession>()
                .eq("shop_id", shopId).eq("state", DrawerSession.STATE_CLOSED)
                .lt(cursor != null, "id", cursor).orderByDesc("id").last("LIMIT " + (pageSize + 1));
        List<DrawerSession> sessions = list(query);
        boolean hasMore = sessions.size() > pageSize;
        if (hasMore) sessions = new ArrayList<>(sessions.subList(0, pageSize));
        List<Map<String, Object>> items = new ArrayList<>();
        for (DrawerSession session : sessions) items.add(getShiftSummaryReport(session.getId()));
        return page(items, sessions.isEmpty() ? null : sessions.get(sessions.size() - 1).getId(), hasMore);
    }

    @Override
    public Map<String, Object> listCashEvents(Integer shopId, Long drawerSessionId, Long cursor, Integer limit) {
        DrawerSession session = getById(drawerSessionId);
        if (session == null || !Objects.equals(shopId, session.getShop_id())) {
            throw new ApiException(404, "SHIFT_NOT_FOUND", "班次不存在");
        }
        if (!DrawerSession.STATE_CLOSED.equals(session.getState())) {
            throw new ApiException(409, "SHIFT_NOT_CLOSED", "班次未交班前不可查看可推导盲盘结果的现金流水");
        }
        int pageSize = clampLimit(limit);
        List<CashMovement> movements = cashMovementMapper.selectList(new QueryWrapper<CashMovement>()
                .eq("shop_id", shopId).eq("drawer_session_id", drawerSessionId)
                .lt(cursor != null, "id", cursor).orderByDesc("id").last("LIMIT " + (pageSize + 1)));
        boolean hasMore = movements.size() > pageSize;
        if (hasMore) movements = new ArrayList<>(movements.subList(0, pageSize));
        List<Map<String, Object>> items = new ArrayList<>();
        for (CashMovement movement : movements) {
            Map<String, Object> event = safeLatestMovement(movement, true);
            event.put("reference_no", movement.getMovement_no());
            items.add(event);
        }
        return page(items, movements.isEmpty() ? null : movements.get(movements.size() - 1).getId(), hasMore);
    }

    private String adminName(Integer adminId) {
        if (adminId == null || adminService == null) return null;
        return AdminNameResolver.resolveDisplayName(adminId, adminService);
    }

    private static Map<String, Object> identity(Object id, String displayName) {
        Map<String, Object> map = new LinkedHashMap<>();
        map.put("id", id);
        map.put("display_name", displayName);
        return map;
    }

    private static Map<String, Object> drawerIdentity(DrawerSession session) {
        Map<String, Object> map = identity(session.getId(), session.getDrawer_code());
        map.put("session_id", session.getId());
        map.put("code", session.getDrawer_code());
        return map;
    }

    private static Map<String, Object> safeCurrentShift(DrawerSession session) {
        Map<String, Object> map = new LinkedHashMap<>();
        map.put("session_id", session.getId());
        map.put("session_no", session.getSession_no());
        map.put("state", session.getState());
        map.put("opened_at", session.getOpened_at());
        map.put("business_day", session.getBusiness_day());
        return map;
    }

    private Map<String, Object> safeLatestMovement(CashMovement movement, boolean includeAmount) {
        Map<String, Object> map = new LinkedHashMap<>();
        map.put("event_id", movement.getId());
        map.put("type", movement.getMovement_type());
        if (includeAmount) map.put("amount_fen", movement.getAmount_fen());
        map.put("amount_hidden", !includeAmount);
        map.put("occurred_at", movement.getOccurred_at());
        map.put("operator_name", adminName(movement.getOperator_id()));
        return map;
    }

    private static Map<String, Object> page(List<Map<String, Object>> items, Long cursor, boolean hasMore) {
        Map<String, Object> result = new LinkedHashMap<>();
        result.put("items", items);
        result.put("next_cursor", hasMore ? cursor : null);
        result.put("has_more", hasMore);
        return result;
    }

    private static int clampLimit(Integer limit) {
        return limit == null ? 20 : Math.max(1, Math.min(limit, 100));
    }

    /**
     * 交班报告交易明细汇总：订单销售（总营收/优惠/退款/赠送金实付/净营收）、找零、退菜与赠菜。
     * 数据窗口 = 该钱箱会话成功支付台账关联的已结订单（与 channels 同源），异常时降级为空汇总，不影响主报表。
     */
    private void appendTransactionDetails(Map<String, Object> report, List<PaymentLedger> ledgers,
                                          DrawerSession session, long drawerSessionId) {
        Map<String, Object> orderSalesSummary = new LinkedHashMap<>();
        Map<String, Object> changeSummary = new LinkedHashMap<>();
        Map<String, Object> dishOperations = new LinkedHashMap<>();
        try {
            java.util.Set<String> paidOrderNos = new java.util.LinkedHashSet<>();
            if (ledgers != null) {
                for (PaymentLedger pl : ledgers) {
                    if (pl != null && StringUtils.hasText(pl.getOrder_no())) {
                        paidOrderNos.add(pl.getOrder_no());
                    }
                }
            }
            if (!paidOrderNos.isEmpty() && orderService != null) {
                QueryWrapper<Order> q = new QueryWrapper<Order>().in("order_no", paidOrderNos);
                if (session != null && session.getShop_id() != null) {
                    q.eq("shop_id", session.getShop_id());
                }
                List<Order> paidOrders = orderService.list(q);
                if (paidOrders != null && !paidOrders.isEmpty()) {
                    long grossFen = 0L, discountFen = 0L, refundFen = 0L, giftFen = 0L, netFen = 0L, changeFen = 0L;
                    Map<String, Long> changeByChannel = new LinkedHashMap<>();
                    java.util.List<Integer> orderIds = new java.util.ArrayList<>();
                    for (Order order : paidOrders) {
                        long sett = toFen(order.getSett_amount());
                        long serviceFee = toFen(order.getService_fee());
                        long discount = toFen(order.getDiscount_amount());
                        long refund = toFen(order.getRefund_amount());
                        long giftPaid = toFen(order.getPay_amount_gift());
                        grossFen += sett + serviceFee;
                        discountFen += discount;
                        refundFen += refund;
                        giftFen += giftPaid;
                        netFen += sett + serviceFee - discount - refund - giftPaid;
                        long change = toFen(order.getCheckout_change_amount());
                        if (change > 0) {
                            changeFen += change;
                            String channel = order.getCheckout_change_channel();
                            if (!StringUtils.hasText(channel)) channel = "cash";
                            changeByChannel.merge(channel, change, Long::sum);
                        }
                        if (order.getId() != null) orderIds.add(order.getId());
                    }
                    orderSalesSummary.put("paid_order_count", paidOrders.size());
                    orderSalesSummary.put("gross_sales_fen", grossFen);
                    orderSalesSummary.put("discount_fen", discountFen);
                    orderSalesSummary.put("refund_fen", refundFen);
                    orderSalesSummary.put("gift_paid_fen", giftFen);
                    orderSalesSummary.put("net_sales_fen", netFen);
                    changeSummary.put("total_change_fen", changeFen);
                    changeSummary.put("by_channel", changeByChannel);

                    if (!orderIds.isEmpty() && orderDetailService != null) {
                        QueryWrapper<OrderDetail> dq = new QueryWrapper<OrderDetail>()
                                .in("m_id", orderIds)
                                .ne("line_type", "combo_component");
                        List<OrderDetail> details = orderDetailService.list(dq);
                        if (details != null && !details.isEmpty()) {
                            long refundCount = 0L, refundAmountFen = 0L, giveCount = 0L;
                            for (OrderDetail detail : details) {
                                if (detail == null) continue;
                                if ("refunded".equals(detail.getLine_status())) {
                                    long refundedQty = detail.getRefunded_quantity() != null
                                            ? detail.getRefunded_quantity() : 0L;
                                    long qty = toLong(detail.getQuantity());
                                    long totalPriceFen = toFen(detail.getTotal_price());
                                    refundCount += refundedQty;
                                    if (refundedQty > 0 && qty > 0) {
                                        refundAmountFen += Math.round(totalPriceFen * refundedQty * 1.0 / qty);
                                    } else if (refundedQty > 0) {
                                        refundAmountFen += totalPriceFen;
                                    }
                                } else if (!"refunded".equals(detail.getLine_status())
                                        && detail.getTotal_price() != null
                                        && Math.abs(detail.getTotal_price()) < 0.005) {
                                    // 赠菜：单价 0 的普通行（排除退菜与套餐子项）
                                    giveCount += toLong(detail.getQuantity());
                                }
                            }
                            dishOperations.put("refund_dish_count", refundCount);
                            dishOperations.put("refund_dish_amount_fen", refundAmountFen);
                            dishOperations.put("give_dish_count", giveCount);
                            dishOperations.put("give_dish_amount_fen", 0L);
                        }
                    }
                }
            }
        } catch (Exception ex) {
            log.warn("交班报告交易明细汇总失败 drawerSessionId={}: {}", drawerSessionId, ex.getMessage());
        }
        report.put("order_sales_summary", orderSalesSummary);
        report.put("change_summary", changeSummary);
        report.put("dish_operations", dishOperations);
    }

    private static long toFen(Double yuan) {
        if (yuan == null) return 0L;
        return Math.round(yuan * 100.0);
    }

    private static long toLong(String value) {
        if (value == null || value.trim().isEmpty()) return 0L;
        try {
            return (long) Double.parseDouble(value.trim());
        } catch (NumberFormatException ex) {
            return 0L;
        }
    }

    private Map<String, String> loadPaymentMethods(List<PaymentLedger> ledgers, Integer shopId) {        Map<String, String> methods = new LinkedHashMap<>();
        if (orderService == null || ledgers == null || ledgers.isEmpty()) return methods;
        java.util.Set<String> orderNos = new java.util.LinkedHashSet<>();
        for (PaymentLedger ledger : ledgers) {
            if (ledger != null && StringUtils.hasText(ledger.getOrder_no())) {
                orderNos.add(ledger.getOrder_no());
            }
        }
        if (orderNos.isEmpty()) return methods;
        QueryWrapper<Order> query = new QueryWrapper<Order>().in("order_no", orderNos);
        if (shopId != null) query.eq("shop_id", shopId);
        List<Order> orders = orderService.list(query);
        if (orders == null) return methods;
        for (Order order : orders) {
            if (order != null && StringUtils.hasText(order.getOrder_no())) {
                methods.put(order.getOrder_no(), order.getPayment_method());
            }
        }
        return methods;
    }

    private static String sha256(String value) {
        try {
            byte[] digest = MessageDigest.getInstance("SHA-256").digest(value.getBytes(StandardCharsets.UTF_8));
            StringBuilder out = new StringBuilder();
            for (byte b : digest) out.append(String.format("%02x", b & 0xff));
            return out.toString();
        } catch (Exception ex) {
            throw new IllegalStateException("SHA-256 unavailable", ex);
        }
    }

    private static double fenToYuan(int fen) {
        return BigDecimal.valueOf(fen, 2).doubleValue();
    }
}
