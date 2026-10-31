package com.lanf.entity;

import com.baomidou.mybatisplus.annotation.TableField;
import com.baomidou.mybatisplus.annotation.TableName;
import com.fasterxml.jackson.annotation.JsonAlias;
import com.fasterxml.jackson.annotation.JsonProperty;
import com.fasterxml.jackson.databind.annotation.JsonSerialize;
import lombok.Data;

import java.util.Date;
import java.util.List;
import java.util.Map;

/**
 * 订单主表
 */
@TableName("t_order")
@Data
public class Order {

    private Integer id; // 编号

    private String order_no; // 订单号

    /** 并台主单号：若该单作为从单被并入主单所属桌台，则记录主单号；非从单为 NULL */
    private String master_order_no;
    
    private String client_order_id; // LAN客户端稳定业务ID
    
    private Integer revision; // 订单通用版本号

    private String table_number; // 桌号

    private String number_of_diners; // 用餐人数

    private Double sett_amount; // 计算总价

    private Double discount_amount; // 优惠金额

    /** 服务费，按整单金额(sett_amount)的 5% 由后端计算；订单原价 = sett_amount + service_fee，实付 = 订单原价 - 优惠金额 */
    private Double service_fee;

    /** 累计成功退款金额（元），由微信 /order/refund/notify 在 refund_status=SUCCESS 时累加 */
    private Double refund_amount;

    /** 结账状态 success/unsettled/cancelled；是否发生过退款看 refund_amount */
    private String transac_status;

    /** 挂单状态：0未挂单 1挂单中 */
    private Integer hang_status;

    /** 挂单时间 */
    @JsonSerialize(using=CustomDateTimeSerializer.class)
    private Date hang_time;

    /** 挂单原因或备注 */
    private String hang_reason;

    /** 挂单操作员工ID */
    private Integer hang_admin_id;

    private String order_receiving;  // 接单状态

    private String dineInOrTakeOut; // 堂食or打包

    private Integer orderNumber; // 下单次数

    private String remark; // 备注（修正注释）

    private String openid; // 用户标识

    /** 订单关联用户的绑定手机号，仅用于运营/收银响应，不落库 */
    @TableField(exist = false)
    private String member_phone;

    private String pay_openid;//支付者

    private String prepay_id;

    private String transaction_id;

    private String merchantId;

    /** 支付创建时固化的商户配置身份，后续查单/退款不得漂移到新版本。 */
    private Long merchant_config_id;
    private String merchant_key;
    private Integer merchant_config_version;

    /** 门店 ID（连锁），对应 t_order.shop_id；未迁移列为 null */
    private Integer shop_id;

    /** 下单渠道（服务端写入，不采信客户端）：mini_program=cashier/takeout/ai */
    private String order_channel;

    /** 下单管理员 ID（B 端 JWT 解析，收银/后台开单记录操作人；C 端/AI 为 null），关联 t_admin.id */
    private Integer order_admin_id;

    /** 当班收银员 ID，关联 t_admin.id */
    private Integer cashier_id;

    /** 下单管理员真实姓名（非表字段） */
    @TableField(exist = false)
    private String order_admin_name;

    /** 当班收银员真实姓名（非表字段） */
    @TableField(exist = false)
    private String cashier_name;

    /** 当班收银员工号（非表字段） */
    @TableField(exist = false)
    private String cashier_work_no;

    /** 当班收银员复合展示文案，例如 "姓名 (工号)"（非表字段） */
    @TableField(exist = false)
    private String cashier_display_name;

    /** 复合展示名称，兼容前端 display_name 字段（非表字段） */
    @TableField(exist = false)
    private String display_name;

    private Integer notice;

    /** 支付方式文案，如：微信支付、余额支付（与 {@code POST /order/payByBalance} 写入值一致） */
    private String payment_method;

    /** 各渠道实付金额（元）。余额支付且走钱包拆分时：{@code pay_amount_balance} 为本金账户扣款、{@code pay_amount_gift} 为赠送金账户扣款，二者之和为实付 */
    private Double pay_amount_wechat;
    private Double pay_amount_alipay;
    private Double pay_amount_balance;

    /** 余额支付从本金账户扣（元）；与 {@code balance_pay_principal}、{@code pay_amount_balance} 一致 */
    private Double balance_pay_principal;

    /** 余额支付从赠送金账户扣（元）；与 {@code balance_pay_gift_wallet}、{@code pay_amount_gift}（钱包赠送金部分）一致 */
    private Double balance_pay_gift_wallet;

    /** 赠送金渠道实付（元）；纯赠送金收银选路或余额支付中的赠送金账户部分 */
    private Double pay_amount_gift;
    private Double pay_amount_cash;

    /** 结账客人付现金额（元），可大于 {@link #pay_amount_cash}；对应 {@code t_order.checkout_cash_tender} */
    private Double checkout_cash_tender;

    /** 找零金额（元）；对应 {@code t_order.checkout_change_amount} */
    private Double checkout_change_amount;

    /** 找零渠道：wechat / cash / alipay；对应 {@code t_order.checkout_change_channel} */
    private String checkout_change_channel;

    /** 找零渠道中文展示（非表字段），详情/列表序列化时由服务端填充 */
    @TableField(exist = false)
    private String checkout_change_channel_label;

    @JsonSerialize(using=CustomDateTimeSerializer.class)
    private Date pay_time;

    @JsonSerialize(using=CustomDateTimeSerializer.class)
    private Date order_time; // 下单时间

    @JsonSerialize(using=CustomDateTimeSerializer.class)
    private Date off_time; // 订单完成时间

    @TableField(select = false,exist = false)
    private List<OrderDetail> goods_list; // 订单详情

    /** 关联配送单 t_takeout_delivery.id；无外卖配送扩展时为 null（非表字段） */
    @TableField(exist = false)
    private Long takeout_delivery_id;

    /** 配送费（元），与 t_takeout_delivery.delivery_fee 一致；无扩展时为 null（非表字段） */
    @TableField(exist = false)
    private Double delivery_fee;

    /** 实际配送费（元），与 t_takeout_delivery.zsq_actual_fee 一致；无扩展时为 null（非表字段） */
    @TableField(exist = false)
    private Double actual_delivery_fee;

    /** 打包费（元），订单详情接口按有效明细反算派生：打包/外卖单 = ceil(商品小计/100) 元（有商品最低 1 元）；堂食为 0（非表字段） */
    @TableField(exist = false)
    private Double packaging_fee;

    /** 配送履约状态，同 t_takeout_delivery.dispatch_status；无扩展时为 null（非表字段） */
    @TableField(exist = false)
    private String takeout_dispatch_status;

    /** KDS 厨显整单状态 10/20/30/40/90；来自 t_kds_order，非表字段 */
    @TableField(exist = false)
    private Integer kds_order_status;

    /**
     * 后台结账 {@code POST /admin/order/checkout} 可选：现金实付部分（元），写入 {@code pay_amount_cash} 后与
     * {@code payment_method} 推断的主渠道分摊剩余净额；非表字段不落库。
     */
    @TableField(exist = false)
    @JsonProperty("cash_amount")
    @JsonAlias({"checkoutCashAmount", "checkout_cash_amount", "payCashAmount", "pay_cash_amount", "cashAmount"})
    private Double cashAmount;

    /** 请求别名：客人付现（元），非表字段 */
    @TableField(exist = false)
    @JsonAlias({"cash_tender", "cashTender", "tender_amount", "tenderAmount"})
    private Double cashTender;

    /** 请求别名：找零金额（元），非表字段 */
    @TableField(exist = false)
    @JsonAlias({"change_amount", "changeAmount"})
    private Double changeAmount;

    /** 请求别名：找零渠道 wechat/cash/alipay，非表字段 */
    @TableField(exist = false)
    @JsonAlias({"change_channel", "changeChannel"})
    private String changeChannel;

    /** 结账/强制结账可选参数：是否强制结账，需要 admin:manage 权限；非表字段不落库 */
    @TableField(exist = false)
    @JsonProperty("force")
    @JsonAlias({"force_checkout", "forceCheckout"})
    private Boolean force;

    /** 强制结账可选参数：审批令牌；非表字段不落库 */
    @TableField(exist = false)
    @JsonProperty("approvalToken")
    @JsonAlias({"approval_token"})
    private String approvalToken;

    /** 强制结账可选参数：现场主管账号密码凭证 authorization: {account: ..., password: ...}；非表字段不落库 */
    @TableField(exist = false)
    @JsonProperty("authorization")
    private Map<String, Object> authorization;

    /** 收款会话 ID；非表字段不落库 */
    @TableField(exist = false)
    @JsonProperty("collection_session_id")
    @JsonAlias({"collectionSessionId", "session_id", "sessionId"})
    private String collectionSessionId;

}
