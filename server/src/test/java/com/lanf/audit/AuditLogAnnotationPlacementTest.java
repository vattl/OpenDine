package com.lanf.audit;

import com.lanf.audit.annotation.AuditLog;
import com.lanf.audit.diff.OrderRefundDiffProvider;
import com.lanf.audit.diff.DishStockDiffProvider;
import com.lanf.controller.OrderController;
import com.lanf.controller.admin.AdminAnnouncementController;
import com.lanf.controller.admin.AdminCategoryController;
import com.lanf.controller.admin.AdminComboController;
import com.lanf.controller.admin.AdminConfigController;
import com.lanf.controller.admin.AdminCouponController;
import com.lanf.controller.admin.AdminDishController;
import com.lanf.controller.admin.AdminKdsAuthorityController;
import com.lanf.controller.admin.AdminKdsReplicationController;
import com.lanf.controller.admin.AdminMaterialController;
import com.lanf.controller.admin.AdminMemberController;
import com.lanf.controller.admin.AdminOrderController;
import com.lanf.controller.admin.AdminOrderDetailController;
import com.lanf.controller.admin.AdminStockPrepController;
import com.lanf.controller.admin.AdminTableController;
import com.lanf.controller.admin.AdminTakeoutController;
import com.lanf.controller.admin.AdminUnitController;
import com.lanf.controller.cashier.CashierOrderController;
import com.lanf.payment.service.WechatRefundSettlementService;
import org.junit.Test;

import java.lang.reflect.Method;
import java.util.LinkedHashMap;
import java.util.Map;

import static org.junit.Assert.*;

/**
 * 埋点挂载断言：P0 阶段全部 36 个关键方法必须带 @AuditLog 且 action 符合约定。
 * 防止后续重构误删埋点。
 */
public class AuditLogAnnotationPlacementTest {

    private static final Map<Class<?>, Map<String, String>> EXPECTED = new LinkedHashMap<>();

    static {
        Map<String, String> cashier = new LinkedHashMap<>();
        cashier.put("quickOrder", "cashier_order_create");
        cashier.put("addDishes", "cashier_add_dish");
        cashier.put("refundDish", "cashier_refund_dish");
        cashier.put("refund", "cashier_refund_cash");
        cashier.put("updatePrice", "cashier_change_price");
        cashier.put("discount", "cashier_discount");
        cashier.put("checkout", "cashier_checkout");
        cashier.put("unCheckout", "cashier_un_checkout");
        EXPECTED.put(CashierOrderController.class, cashier);

        Map<String, String> dish = new LinkedHashMap<>();
        dish.put("importFromHq", "admin_dish_import");
        dish.put("save", "admin_dish_save");
        dish.put("updateOnSale", "admin_dish_onsale");
        dish.put("updateSaleStatus", "admin_dish_sale_status");
        dish.put("sort", "admin_dish_sort");
        EXPECTED.put(AdminDishController.class, dish);

        Map<String, String> coupon = new LinkedHashMap<>();
        coupon.put("add", "admin_coupon_add");
        coupon.put("createRedeemCodes", "admin_coupon_redeem_create");
        coupon.put("batchSendCoupon", "admin_coupon_batch_send");
        coupon.put("deleteRedeemCodes", "admin_coupon_redeem_delete");
        coupon.put("userCouponGrant", "admin_coupon_user_grant");
        coupon.put("userCouponBatchGrantExcel", "admin_coupon_user_batch_grant");
        coupon.put("userCouponVoid", "admin_coupon_user_void");
        coupon.put("userCouponUnbind", "admin_coupon_user_unbind");
        coupon.put("update", "admin_coupon_update");
        EXPECTED.put(AdminCouponController.class, coupon);

        Map<String, String> member = new LinkedHashMap<>();
        member.put("recharge", "admin_member_recharge");
        member.put("deductBalance", "admin_member_balance_deduct");
        EXPECTED.put(AdminMemberController.class, member);

        Map<String, String> order = new LinkedHashMap<>();
        order.put("receiving", "admin_order_receiving");
        order.put("reassignOpenidByPhone", "admin_order_reassign_openid");
        order.put("rece", "admin_order_rece");
        order.put("checkout", "admin_order_checkout");
        order.put("manualDiscount", "admin_order_discount");
        order.put("addPoints", "admin_order_add_points");
        order.put("setAutoAccept", "admin_order_auto_accept");
        EXPECTED.put(AdminOrderController.class, order);

        Map<String, String> stockprep = new LinkedHashMap<>();
        stockprep.put("bomSave", "admin_stockprep_bom_save");
        stockprep.put("bomDelete", "admin_stockprep_bom_delete");
        stockprep.put("configSave", "admin_stockprep_config_save");
        stockprep.put("planGenerate", "admin_stockprep_plan_generate");
        stockprep.put("planUpdate", "admin_stockprep_plan_update");
        stockprep.put("planBatchStatus", "admin_stockprep_plan_batch_status");
        EXPECTED.put(AdminStockPrepController.class, stockprep);

        Map<String, String> takeout = new LinkedHashMap<>();
        takeout.put("saveConfig", "admin_takeout_config_save");
        takeout.put("updateStatus", "admin_takeout_delivery_status");
        takeout.put("zsqDispatch", "admin_takeout_zsq_dispatch");
        takeout.put("zsqRedispatch", "admin_takeout_zsq_redispatch");
        takeout.put("zsqSync", "admin_takeout_zsq_sync");
        EXPECTED.put(AdminTakeoutController.class, takeout);

        Map<String, String> category = new LinkedHashMap<>();
        category.put("add", "admin_category_add");
        category.put("update", "admin_category_update");
        category.put("sort", "admin_category_sort");
        EXPECTED.put(AdminCategoryController.class, category);

        Map<String, String> unit = new LinkedHashMap<>();
        unit.put("add", "admin_unit_add");
        EXPECTED.put(AdminUnitController.class, unit);

        Map<String, String> combo = new LinkedHashMap<>();
        combo.put("save", "admin_combo_save");
        EXPECTED.put(AdminComboController.class, combo);

        Map<String, String> table = new LinkedHashMap<>();
        table.put("add", "admin_table_add");
        table.put("open", "admin_table_open");
        EXPECTED.put(AdminTableController.class, table);

        Map<String, String> announcement = new LinkedHashMap<>();
        announcement.put("add", "admin_announcement_add");
        announcement.put("update", "admin_announcement_update");
        EXPECTED.put(AdminAnnouncementController.class, announcement);

        Map<String, String> material = new LinkedHashMap<>();
        material.put("save", "admin_material_save");
        material.put("inbound", "admin_material_inbound");
        material.put("outbound", "admin_material_outbound");
        EXPECTED.put(AdminMaterialController.class, material);

        Map<String, String> config = new LinkedHashMap<>();
        config.put("putWechatPrepayNineFold", "admin_config_wechat_prepay_ninefold");
        config.put("putInviteFirstOrderBalanceReward", "admin_config_invite_first_order_reward");
        config.put("putZsqAutoApi", "admin_config_zsq_auto_api");
        config.put("updateInvitePosterConfig", "admin_config_invite_poster");
        EXPECTED.put(AdminConfigController.class, config);

        Map<String, String> kdsRepl = new LinkedHashMap<>();
        kdsRepl.put("retry", "admin_kds_replication_retry");
        kdsRepl.put("replace", "admin_kds_replication_replace");
        kdsRepl.put("discard", "admin_kds_replication_discard");
        EXPECTED.put(AdminKdsReplicationController.class, kdsRepl);

        Map<String, String> kdsAuth = new LinkedHashMap<>();
        kdsAuth.put("setAuthorityDevice", "admin_kds_authority_device");
        EXPECTED.put(AdminKdsAuthorityController.class, kdsAuth);
    }

    @Test
    public void allPlannedMethodsAnnotated() {
        for (Map.Entry<Class<?>, Map<String, String>> e : EXPECTED.entrySet()) {
            Class<?> clazz = e.getKey();
            for (Map.Entry<String, String> m : e.getValue().entrySet()) {
                assertAnnotated(clazz, m.getKey(), m.getValue());
            }
        }
    }

    @Test
    public void adminRefundDishAnnotated() throws Exception {
        Method m = AdminOrderDetailController.class.getMethod("deleteMenu", Map.class);
        AuditLog ann = m.getAnnotation(AuditLog.class);
        assertNotNull("deleteMenu 缺 @AuditLog", ann);
        assertEquals("admin_refund_dish", ann.action());
        assertEquals(DishStockDiffProvider.class, ann.diff());
    }

    @Test
    public void refundApplyAnnotated() throws Exception {
        Method m = OrderController.class.getMethod("refund", Map.class);
        AuditLog ann = m.getAnnotation(AuditLog.class);
        assertNotNull("OrderController.refund(Map) 缺 @AuditLog", ann);
        assertEquals("refund_apply", ann.action());
        assertEquals(OrderRefundDiffProvider.class, ann.diff());
    }

    @Test
    public void refundSettleAnnotated() throws Exception {
        Method m = WechatRefundSettlementService.class.getMethod("settle", String.class, String.class, int.class, String.class);
        AuditLog ann = m.getAnnotation(AuditLog.class);
        assertNotNull("WechatRefundSettlementService.settle 缺 @AuditLog", ann);
        assertEquals("refund_settle", ann.action());
        assertEquals(OrderRefundDiffProvider.class, ann.diff());
    }

    private void assertAnnotated(Class<?> clazz, String methodName, String action) {
        boolean found = false;
        for (Method m : clazz.getDeclaredMethods()) {
            if (!m.getName().equals(methodName)) {
                continue;
            }
            found = true;
            AuditLog ann = m.getAnnotation(AuditLog.class);
            assertNotNull(clazz.getSimpleName() + "." + methodName + " 缺 @AuditLog", ann);
            assertEquals(clazz.getSimpleName() + "." + methodName + " action 不符", action, ann.action());
        }
        assertTrue(clazz.getSimpleName() + "." + methodName + " 方法不存在", found);
    }
}
