package com.lanf.controller;

import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import javax.servlet.http.HttpServletRequest;
import javax.servlet.http.HttpServletResponse;
import java.io.IOException;

/**
 * 退款回调入口，委托 OrderController 统一处理。
 */
@RestController
@RequestMapping("/order")
public class OrderRefundController {

    @Autowired
    private OrderController orderController;

    @PostMapping("/refund/notify")
    public void refundNotify(HttpServletRequest request, HttpServletResponse response) throws IOException {
        orderController.handleRefundNotify(request, response);
    }
}
