package com.lanf.config;

import lombok.Data;
import org.springframework.boot.context.properties.ConfigurationProperties;
import org.springframework.stereotype.Component;

/**
 * 图片访问与按 q 裁图：{@code GET /image/dish/xxx.jpg?q=300} 由服务端缩放后返回。
 */
@Data
@Component
@ConfigurationProperties(prefix = "app.image-serve")
public class ImageServeProperties {

    /** 是否启用 q 裁图；false 时忽略 q 直接返回原图 */
    private boolean resizeEnabled = true;

    /** q 允许的最大值（像素，按宽度等比缩放） */
    private int maxQ = 1200;

    /** q 允许的最小值 */
    private int minQ = 1;
}
