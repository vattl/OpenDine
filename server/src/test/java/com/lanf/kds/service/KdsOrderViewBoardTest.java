package com.lanf.kds.service;

import org.junit.jupiter.api.Test;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertTrue;

/**
 * 订单维度 view=order 数量契约验收（docs/backend_order_view_coordination.md §4.2、§6 A1）。
 */
class KdsOrderViewBoardTest {

    @Test
    void a1_partialCook_notDoneLine() {
        int lineQty = 3;
        int cookedQty = 1;
        int cookRemaining = 2;
        assertEquals(lineQty, cookedQty + cookRemaining);
        assertFalse(KdsOverviewBoardService.isDoneLineInTab(lineQty, cookRemaining, cookedQty));
    }

    @Test
    void a1_fullCook_doneLineStillValid() {
        int lineQty = 3;
        int cookedQty = 3;
        int cookRemaining = 0;
        assertEquals(lineQty, cookedQty + cookRemaining);
        assertTrue(KdsOverviewBoardService.isDoneLineInTab(lineQty, cookRemaining, cookedQty));
    }

    @Test
    void pendingPrep_quantityIdentity() {
        int lineQty = 5;
        int prepQty = 2;
        int prepRemaining = 3;
        assertEquals(lineQty, prepQty + prepRemaining);
        assertFalse(KdsOverviewBoardService.isDoneLineInTab(lineQty, prepRemaining, prepQty));
    }

    @Test
    void readyServe_quantityIdentity() {
        int lineQty = 2;
        int servedQty = 1;
        int serveRemaining = 1;
        assertEquals(lineQty, servedQty + serveRemaining);
        assertFalse(KdsOverviewBoardService.isDoneLineInTab(lineQty, serveRemaining, servedQty));
        assertTrue(KdsOverviewBoardService.isDoneLineInTab(lineQty, 0, lineQty));
    }

    @Test
    void twoLines_independentDoneState() {
        // 油边 3 + 鸡翅 2：鸡翅未制作时油边全部制作完成
        assertTrue(KdsOverviewBoardService.isDoneLineInTab(3, 0, 3));
        assertFalse(KdsOverviewBoardService.isDoneLineInTab(2, 2, 0));
    }
}
