package com.lanf.controller.cashier;

import com.lanf.entity.R;
import com.lanf.payment.service.WechatNativePaymentService;
import com.lanf.util.AdminShopRequest;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import javax.servlet.http.HttpServletRequest;
import java.util.Map;

@RestController
@RequestMapping("/cashier/payment/wechat/native/orders")
public class CashierWechatNativePaymentController {
    @Autowired private WechatNativePaymentService paymentService;
    @Autowired private HttpServletRequest request;

    @PostMapping
    public R create(@RequestBody Map<String, Object> body) {
        return paymentService.create(AdminShopRequest.getResolvedShopId(request),
                text(body.get("orderNo"), body.get("order_no")), text(body.get("terminalId"), body.get("terminal_id")));
    }

    @GetMapping("/{orderNo}")
    public R query(@PathVariable String orderNo) {
        return paymentService.query(AdminShopRequest.getResolvedShopId(request), orderNo);
    }

    @PostMapping("/{orderNo}/close")
    public R close(@PathVariable String orderNo) {
        return paymentService.close(AdminShopRequest.getResolvedShopId(request), orderNo);
    }

    private static String text(Object preferred, Object fallback) {
        Object value = preferred != null ? preferred : fallback;
        return value == null ? null : String.valueOf(value);
    }
}
