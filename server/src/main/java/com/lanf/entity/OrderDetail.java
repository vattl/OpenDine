package com.lanf.entity;

import com.baomidou.mybatisplus.annotation.TableField;
import com.baomidou.mybatisplus.annotation.TableName;
import com.fasterxml.jackson.annotation.JsonProperty;
import lombok.Data;

import java.util.List;
import java.util.Map;


/**
 * 订单详细表
 */
@TableName("t_order_detail")
@Data
public class OrderDetail {

    private Integer id; // 编号

    @TableField("mId")
    private Integer mId; // 订单主表Id

    private String name; // 菜品名称

    private String quantity; // 数量

    private String unit; // 单位

    private String image; // 菜品图片

    private Double total_price; // 总价

    private String Morder_no;

    private Integer Morder_num;

    private String order_rece;

    /** normal=有效明细；refunded=已退菜（不参与计价/KDS，库存已回退） */
    private String line_status;

    private String remark;

    private String selectedSpicy;

    private String cid;

    /** t_dish.id，下单/加菜时写入；KDS 行透出依赖此关联 */
    private Integer dish_id;

    /** 收银端本地购物车行 ID，用于云端正式明细映射与本地 KDS 重建。 */
    private String client_line_id;

    /** 累计已退数量；部分退菜后 quantity 为剩余数量。 */
    private Integer refunded_quantity;

    /** normal / combo_header / combo_component；下单请求可传 combo 表示套餐行（与 combo_id 联用） */
    private String line_type;

    /** t_combo.id */
    private Long combo_id;

    /** 同一订单内同一套餐实例 */
    private String combo_instance_id;

    /** combo 子行指向头行明细 id */
    private Integer parent_detail_id;

    /** 套餐头行：用户选择 JSON，与 combo_selections 二选一传入 */
    private String combo_selection_json;

    /** 仅请求体反序列化，不落库；JSON 字段名 combo_selections */
    @TableField(exist = false)
    @JsonProperty("combo_selections")
    private Map<String, Object> comboSelections;

    @TableField(select = false,exist = false)
    private List<OrderDetail> goods_list; // 订单详情

    /** KDS 制作状态（非表字段，接口层联查填充）：0 待制作 / 1 制作中 / 2 已完成 / 3 已退菜；无工单为 null */
    @TableField(exist = false)
    private Integer kds_item_status;

    /** KDS 制作状态文案：待制作/制作中/已完成/已退菜；无工单为 null */
    @TableField(exist = false)
    private String kds_status_text;

    /** KDS 已传菜确认数量（分批出餐进度）；无工单为 null */
    @TableField(exist = false)
    private Integer kds_served_quantity;

}
