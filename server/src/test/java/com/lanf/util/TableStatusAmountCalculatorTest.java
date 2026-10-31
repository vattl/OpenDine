package com.lanf.util;

import com.lanf.entity.Order;
import com.lanf.entity.OrderDetail;
import org.junit.jupiter.api.Test;

import java.util.Arrays;

import static org.junit.jupiter.api.Assertions.assertEquals;

class TableStatusAmountCalculatorTest {

    @Test
    void calculateUsesPersistedOrderAmountWhenComboDetailsDrift() {
        Order order = new Order();
        order.setSett_amount(116d);
        order.setService_fee(0d);

        TableStatusAmountCalculator.Result result = TableStatusAmountCalculator.calculate(
                order,
                Arrays.asList(
                        detail("combo_header", "normal", "1", 108d),
                        detail("normal", "normal", "1", 8d),
                        detail("normal", "normal", "1", 8d)));

        assertEquals(116d, result.getGoodsAmount());
        assertEquals(116d, result.getPayableAmount());
    }

    @Test
    void calculateExcludesGiftedRefundedAndComboComponentLines() {
        Order order = new Order();
        order.setDiscount_amount(10d);
        order.setRefund_amount(5d);
        order.setPay_amount_gift(3d);
        order.setSett_amount(100d);
        order.setService_fee(5d);

        TableStatusAmountCalculator.Result result = TableStatusAmountCalculator.calculate(
                order,
                Arrays.asList(
                        detail("normal", "normal", "1", 100d),
                        detail("normal", "normal", "2", 0d),
                        detail("normal", "refunded", "1", 50d),
                        detail("combo_component", "normal", "1", 0d)));

        assertEquals(100d, result.getGoodsAmount());
        assertEquals(5d, result.getServiceFee());
        assertEquals(87d, result.getPayableAmount());
        assertEquals(1, result.getGiftedLineCount());
        assertEquals(2, result.getGiftedQuantity());
        assertEquals(1, result.getRefundedLineCount());
    }

    @Test
    void calculateNeverReturnsNegativePayable() {
        Order order = new Order();
        order.setDiscount_amount(99d);

        TableStatusAmountCalculator.Result result = TableStatusAmountCalculator.calculate(
                order, Arrays.asList(detail("normal", "normal", "1", 0d)));

        assertEquals(0d, result.getGoodsAmount());
        assertEquals(0d, result.getPayableAmount());
        assertEquals(1, result.getGiftedLineCount());
    }

    private static OrderDetail detail(String lineType, String lineStatus, String quantity, double total) {
        OrderDetail detail = new OrderDetail();
        detail.setLine_type(lineType);
        detail.setLine_status(lineStatus);
        detail.setQuantity(quantity);
        detail.setTotal_price(total);
        return detail;
    }
}
