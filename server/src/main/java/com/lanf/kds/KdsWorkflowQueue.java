package com.lanf.kds;

import com.baomidou.mybatisplus.core.conditions.query.QueryWrapper;
import com.lanf.kds.entity.KdsTicket;
import org.springframework.util.StringUtils;

import java.util.Locale;

/**
 * 统一工作流看板队列（与 {@code docs/kds_regression_matrix.md}、{@code docs/kds_workflow_refactor_plan.md} 一致）。
 * <p>第一版与存量字段兼容映射：</p>
 * <ul>
 *   <li>{@link #PENDING_PREP} — 待配菜剩余量 {@code line_qty - prep_quantity > 0}</li>
 *   <li>{@link #PENDING_COOK} — 待制作剩余量 {@code prep_quantity - cooked_quantity > 0}</li>
 *   <li>{@link #READY_SERVE} — 待传菜剩余量 {@code cooked_quantity - served_quantity > 0}</li>
 *   <li>{@link #DONE} — {@code archived=1}</li>
 * </ul>
 */
public final class KdsWorkflowQueue {

    public static final String PENDING_PREP = "pending_prep";
    public static final String PENDING_COOK = "pending_cook";
    public static final String READY_SERVE = "ready_serve";
    public static final String DONE = "done";

    private KdsWorkflowQueue() {
    }

    public static String normalize(String queue) {
        if (!StringUtils.hasText(queue)) {
            return PENDING_COOK;
        }
        String q = queue.trim().toLowerCase(Locale.ROOT);
        if ("pending_prep".equals(q) || "prep".equals(q) || "待配菜".equals(queue.trim())) {
            return PENDING_PREP;
        }
        if ("pending_cook".equals(q) || "pending".equals(q) || "cook".equals(q) || "待制作".equals(queue.trim())) {
            return PENDING_COOK;
        }
        if ("ready_serve".equals(q) || "serve".equals(q) || "ready".equals(q) || "待传菜".equals(queue.trim())) {
            return READY_SERVE;
        }
        if ("done".equals(q) || "completed".equals(q) || "archived".equals(q) || "已完成".equals(queue.trim())) {
            return DONE;
        }
        return PENDING_COOK;
    }

    /** 供 {@link com.lanf.kds.service.KdsOverviewBoardService} 使用的 legacy queue 名 */
    public static String toOverviewLegacyQueue(String queue) {
        if (PENDING_PREP.equals(queue)) {
            return PENDING_PREP;
        }
        if (READY_SERVE.equals(queue)) {
            return "ready_serve";
        }
        if (DONE.equals(queue)) {
            return "done";
        }
        if (PENDING_COOK.equals(queue)) {
            return "pending_cook";
        }
        return "pending";
    }

    public static String nextAfter(String fromQueue) {
        if (PENDING_PREP.equals(fromQueue)) {
            return PENDING_COOK;
        }
        if (PENDING_COOK.equals(fromQueue)) {
            return READY_SERVE;
        }
        return DONE;
    }

    /**
     * SQL 粗筛；精确队列剩余量由 {@link com.lanf.kds.support.KdsTicketQuantityUtil} 在业务层二次过滤。
     */
    public static void applyTicketFilter(QueryWrapper<KdsTicket> q, String queue) {
        q.ne("item_status", KdsItemStatus.VOID);
        if (PENDING_PREP.equals(queue) || PENDING_COOK.equals(queue)) {
            q.in("item_status", KdsItemStatus.PENDING, KdsItemStatus.COOKING).eq("archived", 0);
        } else if (READY_SERVE.equals(queue)) {
            q.eq("archived", 0);
        } else if (DONE.equals(queue)) {
            q.eq("archived", 1);
        }
    }
}
