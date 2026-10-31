package com.lanf.service;

import com.baomidou.mybatisplus.extension.service.IService;
import com.lanf.entity.Order;
import com.lanf.entity.OrderInvoice;
import com.lanf.entity.R;

import java.util.Map;

/**
 * 订单电子发票服务接口
 */
public interface IOrderInvoiceService extends IService<OrderInvoice> {

    /**
     * 为订单生成开票二维码
     * @param order 订单对象
     * @param invoiceAmountReq 申请开票金额（为空则默认按订单净营业额）
     * @param taxRate 税率（默认 0.06）
     * @param operatorId 操作人管理员ID
     * @return 包含 orderNo, invoiceStatus, invoiceQrUrl, invoiceAmount, taxRate, expireMinutes, notice 等字段的响应
     */
    R createInvoiceQrcode(Order order, Double invoiceAmountReq, Double taxRate, Integer operatorId);

    /**
     * 查询订单当前的开票状态与详细信息
     * @param order 订单对象
     * @return 包含开票状态、抬头、税号、发票号、PDF链接等信息的响应
     */
    R getInvoiceStatus(Order order);

    /**
     * 顾客公开扫码获取订单发票申请信息（免登录）
     * @param orderNo 订单号
     * @param applyId 申请流水号
     * @param token 防伪令牌
     * @return 订单可开票金额、当前状态、抬头信息
     */
    R getInvoiceInfoForPublic(String orderNo, String applyId, String token);

    /**
     * 顾客自主提交发票抬头信息（免登录）
     * @param orderNo 订单号
     * @param applyId 申请单号
     * @param token 防伪令牌
     * @param titleType 抬头类型（COMPANY/PERSONAL）
     * @param buyerTitle 发票抬头
     * @param buyerTaxNo 纳税人识别号
     * @param buyerEmail 接收发票邮箱
     * @param buyerPhone 联系手机
     * @return 提交结果
     */
    R submitInvoiceTitleFromCustomer(String orderNo, String applyId, String token,
                                     String titleType, String buyerTitle, String buyerTaxNo,
                                     String buyerEmail, String buyerPhone);

    /**
     * 财务/收银员录入已开具的发票数据
     * @param orderNo 订单号
     * @param fapiaoNumber 发票号码
     * @param fapiaoCode 发票代码
     * @param fapiaoFileUrl 电子发票文件下载链接
     * @param operatorId 操作人ID
     * @return 处理结果
     */
    R issueInvoice(String orderNo, String fapiaoNumber, String fapiaoCode, String fapiaoFileUrl, Integer operatorId);

    /**
     * 财务/管理员驳回异常开票申请
     * @param orderNo 订单号
     * @param rejectReason 驳回原因说明
     * @param operatorId 操作人ID
     * @return 处理结果
     */
    R rejectInvoice(String orderNo, String rejectReason, Integer operatorId);

    /**
     * 财务工作台分页查询开票申请列表
     * @param page 页码
     * @param limit 每页数量
     * @param status 状态过滤
     * @param keyword 搜索关键词（订单号/抬头/手机号）
     * @param startDate 开始日期
     * @param endDate 结束日期
     * @param shopId 门店ID
     * @return 包含 total, list, metrics 的分页结果
     */
    R pageInvoiceForAdmin(Integer page, Integer limit, String status, String keyword, String startDate, String endDate, Integer shopId);

    /**
     * 将已开具的发票插入微信用户卡包
     * @param orderNo 订单号
     * @param operatorId 操作人ID
     * @return 插入卡包处理结果
     */
    R insertInvoiceToWechatCard(String orderNo, Integer operatorId);

    /**
     * 处理微信电子发票异步回调（用户抬头填写完成、发票开具成功、发票冲红等）
     * @param headers 请求头
     * @param requestBody 密文数据
     * @return 处理结果
     */
    R handleWechatInvoiceNotify(Map<String, String> headers, String requestBody);
}
