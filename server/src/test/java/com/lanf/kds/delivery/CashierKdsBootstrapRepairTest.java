package com.lanf.kds.delivery;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertNull;

/**
 * CashierKdsBootstrapRepair 补投事件选择逻辑（B 方案）。
 *
 * 覆盖场景：
 * - 接单中未取消订单 → ORDER_ACCEPTED 补投
 * - 已收盘（off_order）订单 → ORDER_CLOSED 补投
 * - 取消单（acceptance/transac_status 任一 cancelled）→ 跳过补投
 */
class CashierKdsBootstrapRepairTest {

    @Test
    @DisplayName("接单中未取消订单补投 ORDER_ACCEPTED")
    void recOrderNotCancelled() {
        assertEquals("ORDER_ACCEPTED", CashierKdsBootstrapRepair.resolveRepairEventType("rec_order", null));
        assertEquals("ORDER_ACCEPTED", CashierKdsBootstrapRepair.resolveRepairEventType("rec_order", "success"));
    }

    @Test
    @DisplayName("已收盘订单补投 ORDER_CLOSED")
    void offOrderPublishesClosed() {
        assertEquals("ORDER_CLOSED", CashierKdsBootstrapRepair.resolveRepairEventType("off_order", null));
        assertEquals("ORDER_CLOSED", CashierKdsBootstrapRepair.resolveRepairEventType("off_order", "success"));
    }

    @Test
    @DisplayName("acceptance=cancelled 取消单跳过补投")
    void cancelledAcceptanceSkipped() {
        assertNull(CashierKdsBootstrapRepair.resolveRepairEventType("cancelled", null));
        assertNull(CashierKdsBootstrapRepair.resolveRepairEventType("cancelled", "success"));
    }

    @Test
    @DisplayName("transac_status=cancelled 取消单跳过补投（优先于收盘状态）")
    void cancelledTransactionSkipped() {
        assertNull(CashierKdsBootstrapRepair.resolveRepairEventType("rec_order", "cancelled"));
        assertNull(CashierKdsBootstrapRepair.resolveRepairEventType("off_order", "cancelled"));
    }
}
