package com.lanf.kds.support;

import com.lanf.kds.KdsItemStatus;
import com.lanf.kds.KdsWorkflowQueue;
import com.lanf.kds.entity.KdsTicket;
import org.springframework.util.StringUtils;

/**
 * 工单数量阶段：待配菜 → 待制作 → 待传菜 → 已完成。
 */
public final class KdsTicketQuantityUtil {

    private KdsTicketQuantityUtil() {
    }

    public static int lineQuantity(String quantityRaw) {
        if (!StringUtils.hasText(quantityRaw)) {
            return 1;
        }
        try {
            return Math.max(1, (int) Math.round(Double.parseDouble(quantityRaw.trim())));
        } catch (NumberFormatException e) {
            return 1;
        }
    }

    public static int prepQuantity(KdsTicket ticket) {
        return ticket != null && ticket.getPrep_quantity() != null ? Math.max(0, ticket.getPrep_quantity()) : 0;
    }

    public static int cookedQuantity(KdsTicket ticket, int lineQty) {
        if (ticket == null) {
            return 0;
        }
        if (ticket.getCooked_quantity() != null) {
            return Math.max(0, ticket.getCooked_quantity());
        }
        Integer status = ticket.getItem_status();
        if (status != null && status == KdsItemStatus.DONE) {
            return lineQty;
        }
        return 0;
    }

    public static int servedQuantity(KdsTicket ticket) {
        return ticket != null && ticket.getServed_quantity() != null ? Math.max(0, ticket.getServed_quantity()) : 0;
    }

    public static int prepRemaining(KdsTicket ticket, int lineQty) {
        return Math.max(0, lineQty - prepQuantity(ticket));
    }

    public static int cookRemaining(KdsTicket ticket, int lineQty) {
        return Math.max(0, prepQuantity(ticket) - cookedQuantity(ticket, lineQty));
    }

    public static int serveRemaining(KdsTicket ticket, int lineQty) {
        return Math.max(0, cookedQuantity(ticket, lineQty) - servedQuantity(ticket));
    }

    public static boolean hasQueueWork(KdsTicket ticket, int lineQty, String queue) {
        if (ticket == null || ticket.getItem_status() != null && ticket.getItem_status() == KdsItemStatus.VOID) {
            return false;
        }
        if (ticket.getArchived() != null && ticket.getArchived() == 1) {
            return KdsWorkflowQueue.DONE.equals(queue);
        }
        String q = KdsWorkflowQueue.normalize(queue);
        if (KdsWorkflowQueue.PENDING_PREP.equals(q)) {
            return prepRemaining(ticket, lineQty) > 0;
        }
        if (KdsWorkflowQueue.PENDING_COOK.equals(q)) {
            return cookRemaining(ticket, lineQty) > 0;
        }
        if (KdsWorkflowQueue.READY_SERVE.equals(q)) {
            return serveRemaining(ticket, lineQty) > 0;
        }
        if (KdsWorkflowQueue.DONE.equals(q)) {
            return ticket.getArchived() != null && ticket.getArchived() == 1;
        }
        return true;
    }

    public static int displayQuantity(KdsTicket ticket, int lineQty, String queue) {
        String q = KdsWorkflowQueue.normalize(queue);
        if (KdsWorkflowQueue.PENDING_PREP.equals(q)) {
            return prepRemaining(ticket, lineQty);
        }
        if (KdsWorkflowQueue.PENDING_COOK.equals(q)) {
            return cookRemaining(ticket, lineQty);
        }
        if (KdsWorkflowQueue.READY_SERVE.equals(q)) {
            return serveRemaining(ticket, lineQty);
        }
        return lineQty;
    }

    /** 明细数量变更或退菜后，收敛工单各阶段数量。 */
    public static void clampQuantities(KdsTicket ticket, int lineQty) {
        if (ticket == null) {
            return;
        }
        int prep = Math.min(prepQuantity(ticket), lineQty);
        int cooked = Math.min(cookedQuantity(ticket, lineQty), prep);
        int served = Math.min(servedQuantity(ticket), cooked);
        ticket.setPrep_quantity(prep);
        ticket.setCooked_quantity(cooked);
        ticket.setServed_quantity(served);
        if (lineQty <= 0) {
            ticket.setItem_status(KdsItemStatus.VOID);
            return;
        }
        if (served >= lineQty && cooked >= lineQty) {
            ticket.setArchived(1);
        }
        if (prep >= lineQty) {
            ticket.setSkewer_picked(1);
        }
    }

    /**
     * 判定工单是否已完全通过指定队列阶段（用于推进命令幂等自愈）。
     */
    public static boolean isPastQueue(KdsTicket ticket, int lineQty, String fromQueue) {
        if (ticket == null || Integer.valueOf(KdsItemStatus.VOID).equals(ticket.getItem_status())) {
            return false;
        }
        String q = KdsWorkflowQueue.normalize(fromQueue);
        if (ticket.getArchived() != null && ticket.getArchived() == 1) {
            return !KdsWorkflowQueue.DONE.equals(q);
        }
        int prepQty = prepQuantity(ticket);
        int cookedQty = cookedQuantity(ticket, lineQty);
        int servedQty = servedQuantity(ticket);

        if (KdsWorkflowQueue.PENDING_PREP.equals(q)) {
            return prepRemaining(ticket, lineQty) == 0 && (prepQty > 0 || cookedQty > 0 || servedQty > 0);
        }
        if (KdsWorkflowQueue.PENDING_COOK.equals(q)) {
            return cookRemaining(ticket, lineQty) == 0 && (cookedQty > 0 || servedQty > 0);
        }
        if (KdsWorkflowQueue.READY_SERVE.equals(q)) {
            return serveRemaining(ticket, lineQty) == 0 && servedQty > 0;
        }
        return false;
    }

    /**
     * 计算工单当前所在的主业务队列。
     */
    public static String resolveCurrentQueue(KdsTicket ticket, int lineQty) {
        if (ticket == null || Integer.valueOf(KdsItemStatus.VOID).equals(ticket.getItem_status())) {
            return KdsWorkflowQueue.DONE;
        }
        if (ticket.getArchived() != null && ticket.getArchived() == 1) {
            return KdsWorkflowQueue.DONE;
        }
        if (serveRemaining(ticket, lineQty) > 0) {
            return KdsWorkflowQueue.READY_SERVE;
        }
        if (cookRemaining(ticket, lineQty) > 0) {
            return KdsWorkflowQueue.PENDING_COOK;
        }
        if (prepRemaining(ticket, lineQty) > 0) {
            return KdsWorkflowQueue.PENDING_PREP;
        }
        return KdsWorkflowQueue.DONE;
    }
}
