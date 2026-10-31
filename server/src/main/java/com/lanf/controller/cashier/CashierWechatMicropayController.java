package com.lanf.controller.cashier;

import com.lanf.entity.R;
import com.lanf.payment.service.WechatMicropayService;
import com.lanf.util.AdminShopRequest;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.web.bind.annotation.*;

import javax.servlet.http.HttpServletRequest;
import java.util.Map;

@RestController
@RequestMapping("/cashier/payment/wechat/micropay/orders")
public class CashierWechatMicropayController {
    @Autowired private WechatMicropayService paymentService;
    @Autowired private HttpServletRequest request;

    @PostMapping
    public R pay(@RequestBody Map<String, Object> body) {
        return paymentService.pay(AdminShopRequest.getResolvedShopId(request),
                text(body.get("orderNo"), body.get("order_no")),
                text(body.get("authCode"), body.get("auth_code")),
                text(body.get("terminalId"), body.get("terminal_id")), request.getRemoteAddr());
    }

    @GetMapping("/{orderNo}")
    public R query(@PathVariable String orderNo) {
        return paymentService.query(AdminShopRequest.getResolvedShopId(request), orderNo);
    }

    @PostMapping("/{orderNo}/reverse")
    public R reverse(@PathVariable String orderNo) {
        return paymentService.reverse(AdminShopRequest.getResolvedShopId(request), orderNo);
    }

    private static String text(Object preferred, Object fallback) {
        Object value = preferred != null ? preferred : fallback;
        return value == null ? null : String.valueOf(value);
    }
}
