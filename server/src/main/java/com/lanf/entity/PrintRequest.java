package com.lanf.entity;

import lombok.Data;

@Data
public class PrintRequest {
    /** 门店 ID（保留字段，凭据不再按门店解析） */
    private Integer shop_id;
    /** t_printing_device 设备 ID：飞鹅凭据（url/user/ukey）统一从该设备 connection_json 获取 */
    private Long deviceId;
    /** 打印机 SN；为空时使用设备 connection_json 中的 sn */
    private String printerSn;
    private String content;
    private int times = 1;
    private String key;
    private String name;
}
