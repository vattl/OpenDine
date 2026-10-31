package com.lanf.dto;

import com.fasterxml.jackson.annotation.JsonAlias;
import com.fasterxml.jackson.annotation.JsonIgnoreProperties;
import lombok.Data;

/**
 * 公告新增/编辑请求体（camelCase；兼容 snake_case；日期为字符串避免反序列化 400）。
 */
@Data
@JsonIgnoreProperties(ignoreUnknown = true)
public class AnnouncementSaveDTO {

    private Long id;

    private String title;

    private String content;

    private Integer status;

    @JsonAlias("sort_order")
    private Integer sortOrder;

    @JsonAlias("shop_id")
    private Integer shopId;

    /** 支持 yyyy-MM-dd HH:mm:ss、yyyy-MM-dd、ISO-8601（含 Z）等 */
    @JsonAlias("start_time")
    private String startTime;

    @JsonAlias("end_time")
    private String endTime;
}
