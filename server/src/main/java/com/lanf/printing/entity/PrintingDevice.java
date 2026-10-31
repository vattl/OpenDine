package com.lanf.printing.entity;

import com.baomidou.mybatisplus.annotation.IdType;
import com.baomidou.mybatisplus.annotation.TableId;
import com.baomidou.mybatisplus.annotation.TableName;
import lombok.Data;

import java.time.LocalDateTime;

/**
 * 打印设备，对应 t_printing_device（docs/db_migration_printing.sql）。
 * connection_json 存储连接参数（IP/端口/序列号 sn/密钥 key 等），
 * 接口返回前必须经 PrintingService.maskConnection 脱敏，绝不明文回传。
 */
@TableName("t_printing_device")
@Data
public class PrintingDevice {

    @TableId(type = IdType.AUTO)
    private Long id;

    /** t_shop.id，门店隔离维度 */
    private Integer shop_id;

    /** 设备名称 */
    private String name;

    /** 连接方式：LAN/USB/BLUETOOTH/CLOUD */
    private String transport;

    /** 品牌/型号 */
    private String brand;

    /** 连接参数 JSON */
    private String connection_json;

    /** 运行状态：ONLINE/OFFLINE/UNKNOWN */
    private String status;

    /** 乐观锁版本，从 1 起 */
    private Integer version;

    private LocalDateTime created_at;

    private LocalDateTime updated_at;
}
