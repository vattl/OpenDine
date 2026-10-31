package com.lanf.controller.cashier;

import com.lanf.controller.OrderController;
import com.lanf.entity.R;
import com.lanf.util.AdminShopRequest;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import javax.servlet.http.HttpServletRequest;
import java.util.Map;

/**
 * 收银端营业状态：开门 / 打烊。
 * 业务逻辑与运营端 {@code POST /order/ChangeBusiness} 共用
 * （OrderController#changeBusinessCore，含开门强制开班 / 关门强制交班·日结 / force 逃生）。
 * <p>权限码：cashier:operate（force=1 强制跳过需 admin:manage，由核心逻辑内部校验）。</p>
 */
@RestController
@RequestMapping("/cashier/shop")
public class CashierShopBusinessController {

    @Autowired
    private OrderController orderController;

    @PostMapping("/business")
    public R business(@RequestBody(required = false) Map<String, String> body, HttpServletRequest request) {
        Integer shopId = AdminShopRequest.getResolvedShopId(request);
        if (shopId == null || shopId <= 0) {
            return R.error(4001, "缺少门店上下文（X-Shop-Id）");
        }
        return orderController.changeBusinessCore(shopId, body, request);
    }
}
