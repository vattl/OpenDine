package com.lanf.controller;

import com.lanf.entity.R;
import com.lanf.service.IOrderInvoiceService;
import lombok.Data;
import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.util.StringUtils;
import org.springframework.web.bind.annotation.*;

/**
 * 顾客端免登录电子发票自助申请控制器
 * 供顾客通过手机扫码打开 H5 页面查询订单可开票信息并自主录入个人/企业发票抬头
 */
@Slf4j
@CrossOrigin
@RestController
@RequestMapping({"/public/invoice", "/api/invoice", "/order/invoice/public"})
public class PublicInvoiceController {

    @Autowired
    private IOrderInvoiceService orderInvoiceService;

    /**
     * 查询订单发票申请信息（免登录，凭令牌防伪）
     */
    @GetMapping("/info")
    public R getInvoiceInfo(@RequestParam("orderNo") String orderNo,
                           @RequestParam(value = "applyId", required = false) String applyId,
                           @RequestParam("token") String token) {
        if (!StringUtils.hasText(token)) {
            return R.error(401, "缺少安全令牌或令牌已失效");
        }
        return orderInvoiceService.getInvoiceInfoForPublic(orderNo, applyId, token);
    }

    /**
     * 顾客提交发票抬头（免登录，凭令牌防伪）
     */
    @PostMapping("/submit")
    public R submitInvoiceTitle(@RequestBody CustomerInvoiceSubmitReq req) {
        if (req == null) {
            return R.error(400, "请求体不能为空");
        }
        if (!StringUtils.hasText(req.getToken())) {
            return R.error(401, "缺少安全令牌或令牌已失效");
        }
        return orderInvoiceService.submitInvoiceTitleFromCustomer(
                req.getOrderNo(),
                req.getApplyId(),
                req.getToken(),
                req.getTitleType(),
                req.getBuyerTitle(),
                req.getBuyerTaxNo(),
                req.getBuyerEmail(),
                req.getBuyerPhone()
        );
    }

    @Data
    public static class CustomerInvoiceSubmitReq {
        private String orderNo;
        private String applyId;
        private String token;
        private String titleType; // COMPANY or PERSONAL
        private String buyerTitle;
        private String buyerTaxNo;
        private String buyerEmail;
        private String buyerPhone;
    }
}
