package com.lanf.dto;

import com.baomidou.mybatisplus.annotation.TableField;
import com.fasterxml.jackson.annotation.JsonIgnoreProperties;
import com.fasterxml.jackson.annotation.JsonAlias;
import com.fasterxml.jackson.annotation.JsonProperty;
import com.fasterxml.jackson.databind.annotation.JsonSerialize;
import com.lanf.entity.CustomDateTimeSerializer;
import com.lanf.entity.OrderDetail;
import lombok.Data;

import java.util.Date;
import java.util.List;

@Data
@JsonIgnoreProperties(ignoreUnknown = true)
public class OrderDTO {

    @JsonProperty("expectedVersion")
    @JsonAlias("expected_version")
    private Integer expectedVersion;

    private Integer id; // 编号

    private String order_no; // 订单号

    private String table_number; // 桌号

    private String number_of_diners; // 用餐人数

    private Double sett_amount; // 计算总价

    /** 外卖配送费（元）；仅外卖创单时由服务端写入，参与 sett_amount=商品+打包费+配送费 */
    private Double delivery_fee;

    private Double discount_amount; // 优惠金额

    /** 新年服务费；订单原价 = 商品原价 + 打包费 + 服务费 */
    private Double service_fee;

    /** 累计成功退款金额（元） */
    private Double refund_amount;

    private String transac_status; // 结账状态

    private String order_receiving;  // 接单状态

    private String dineInOrTakeOut; // 堂食or打包

    private Integer orderNumber; // 下单次数

    private String remark; // 备注（修正注释）

    private String openid; // 用户标识

    private String pay_openid;//支付者

    private String prepay_id;

    private String transaction_id;

    private String merchantId;

    /** 连锁：门店 ID，可与请求头 X-Shop-Id 合并 */
    private Integer shop_id;

    /** 下单渠道（服务端写入并覆盖，不采信客户端）：cashier/takeout/ai/mini_program */
    private String order_channel;

    /** 下单管理员 ID（B 端 JWT 解析并覆盖；C 端/AI 为 null） */
    private Integer order_admin_id;

    /** 当班收银员 ID，关联 t_admin.id */
    private Integer cashier_id;

    /** 下单管理员真实姓名 */
    private String order_admin_name;

    /** 当班收银员真实姓名 */
    private String cashier_name;

    /** 当班收银员工号 */
    private String cashier_work_no;

    /** 当班收银员复合展示文案 */
    private String cashier_display_name;

    /** 复合展示名称，兼容前端 display_name 字段 */
    private String display_name;

    /** 连锁：门店编码（t_shop.code），可与 shop_id 同时传，须指向同一营业门店 */
    private String shop_code;

    private Integer notice;

    private String payment_method;

    @JsonSerialize(using= CustomDateTimeSerializer.class)
    private Date pay_time;

    @JsonSerialize(using=CustomDateTimeSerializer.class)
    private Date order_time; // 下单时间

    @TableField(select = false,exist = false)
    private List<OrderDetail> goods_list; // 订单详情

    private Long coupon_id;



}
