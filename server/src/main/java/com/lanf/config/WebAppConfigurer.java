package com.lanf.config;

import com.lanf.interceptor.SysInterceptor;
import com.lanf.interceptor.UserIdentityInterceptor;
import com.lanf.kds.interceptor.KdsDeviceAuthInterceptor;
import com.lanf.kds.interceptor.KdsLegacyWriteRetirementInterceptor;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Configuration;
import org.springframework.web.servlet.config.annotation.CorsRegistry;
import org.springframework.web.servlet.config.annotation.InterceptorRegistry;
import org.springframework.web.servlet.config.annotation.ResourceHandlerRegistry;
import org.springframework.web.servlet.config.annotation.WebMvcConfigurer;

import java.util.ArrayList;
import java.util.Arrays;
import java.util.List;

@Configuration
public class WebAppConfigurer implements WebMvcConfigurer {

    @Autowired
    private SysInterceptor sysInterceptor;
    @Autowired
    private KdsDeviceAuthInterceptor kdsDeviceAuthInterceptor;
    @Autowired
    private KdsLegacyWriteRetirementInterceptor kdsLegacyWriteRetirementInterceptor;
    @Autowired
    private UserIdentityInterceptor userIdentityInterceptor;
    @Value("${appPackagesFilePath:/www/wwwroot/upload/packages/}")
    private String appPackagesFilePath;

    // 定义「无需拦截」的公开路径（包含接口、错误页面、静态资源）
    private static final List<String> EXCLUDE_PATHS = Arrays.asList(
            // 业务公开接口（已包含你的原有接口）
            "/adminLogin",
            "/product/**",
            "/invite/**",
            "/category/**",
            "/activity/popup",
            "/activity/popupList",
            "/activity/getCarouselDetail",
            "/bigType/**",
            "/users/wxlogin",
            "/coupon/**", // 优惠券相关接口（免签）
            "/weixinpay/**",
            "/dish/**",
            "/combo/**",
            "/shop/**",
            "/announcement/**", // C 端门店公告，免签（与 openapi 一致）
            "/queue/**", // C 端排队取号，免登录
            "/takeout/**",
            "/parking/**",
            "/user/**",
            "/config/wechat-prepay-ninefold", // 夜间九折规则只读，免签
            "/config/payment-capabilities", // 门店支付能力只读，免签
            "/config/invite-first-order-balance-reward", // 邀请首单余额返利规则只读，免签
            "/config/contact", // C 端联系电话与基础配置，免签
            "/config/subscribe-templates", // 微信订阅消息模板 ID，免签
            "/config/app", // 小程序端通用配置，免签
            "/help/**", // 帮助中心与 FAQ，免签
            "/image/**", // 图片资源（可选 ?q= 服务端裁图），免签
            "/packages/**", // 客户端更新安装包下载，免签
            "/admin/app/version", // 客户端版本检测（启动及免登录支持），免签
            "/admin/app/packages/**", // 客户端安装包直接下载（适配 /admin/ 代理），免签
            "/admin/table/qrcode", // 桌台微信小程序码直接获取与下载，免签
            "/order/**",
            // The landing page is scanned by customers. Creating or confirming
            // a cashier collection session still requires the admin JWT.
            "/pay/offline-collect/jump",
            "/api/v1/personal-alipay/**", // 个人支付宝/微信收款监听 App 回调与 ping，免 JWT
            "/api/v1/notifications/**", // 统一实时消息通道增量同步与已读确认（支持 C 端 X-User-Token 与 B 端双轨）
            "/api/zsq/**", // 真省钱对接（使用真省钱 token，非本系统 JWT）
            "/api/v1/ai/**", // AI 智能配餐与点餐会话链路（小程序 C 端及智能体公开）
            "/api/v1/subscribe/**", // C 端微信订阅消息决策与授权回传，免签
            "/mcp/v1/**", // 标准远程 MCP 工具协议端点
            "/kds/**", // 厨显端：X-Kds-Device-Token，由 KdsDeviceAuthInterceptor 校验
            "/api/v1/kds/**", // 厨显端 v1 别名路径
            "/ws/**",
            // 错误页面（必须放行，避免二次报错）
            "/error",
            // 静态资源（放行所有常见静态资源后缀）
            "/**.js",
            "/**.css",
            "/**.jpg",
            "/**.png",
            "/**.gif",
            "/**.ico",
            "/**.svg",
            // 若静态资源放在 /static 目录下，可直接放行目录（可选）
            "/static/**",
            "/public/**",
            "/api/invoice/**",
            "/order/invoice/public/**",
            "/invoice/**",
            "/invoice-apply.html",
            "/resources/**",
            "/META-INF/resources/**",
            "/kds-demo.html",
            "/feishu/**",
            "/api/feishu/**",
            "/bbq/**",
            "/api/bbq/**"
    );

    /**
     * CORS：厨显/管理端用 Header 鉴权，不用 Cookie；{@code allowCredentials(true)} 与 {@code *} 源互斥会导致浏览器 Failed to fetch。
     */
    @Override
    public void addCorsMappings(CorsRegistry registry) {
        registry.addMapping("/**")
                .allowedOrigins("*")
                .allowCredentials(false)
                .allowedMethods("GET", "HEAD", "POST", "PUT", "DELETE", "OPTIONS")
                .allowedHeaders("*")
                .maxAge(3600);
    }

    /**
     * 配置拦截器规则（放行公开路径；/admin 需 JWT + 权限码，见 docs/权限设计.md）
     */
    @Override
    public void addInterceptors(InterceptorRegistry registry) {
        registry.addInterceptor(sysInterceptor)
                .addPathPatterns("/**")
                .excludePathPatterns(EXCLUDE_PATHS.toArray(new String[0]));
        registry.addInterceptor(sysInterceptor)
                .addPathPatterns(
                        "/order/ChangeBusiness",
                        "/order/ChangeIsReview",
                        "/order/notice",
                        "/order/printContent",
                        "/order/autoAcceptAndPrint",
                        "/order/delete/*");
        registry.addInterceptor(kdsDeviceAuthInterceptor)
                .addPathPatterns("/kds/**", "/api/v1/kds/**")
                .excludePathPatterns("/kds/device/login", "/api/v1/kds/devices/login", "/api/v1/kds/device/login");
        registry.addInterceptor(kdsLegacyWriteRetirementInterceptor)
                .addPathPatterns("/kds/**", "/api/v1/kds/**");
        registry.addInterceptor(userIdentityInterceptor)
                .addPathPatterns("/order/**", "/coupon/**", "/invite/**", "/queue/**",
                        "/takeout/**", "/parking/**", "/user/**");
    }

    /**
     * 静态资源映射（保留原有自定义映射，补充默认静态资源目录）
     */
    @Override
    public void addResourceHandlers(ResourceHandlerRegistry registry) {
        // /image/** 由 ImageServeController 统一输出（支持 ?q= 裁图），不再走静态目录映射

        List<String> packageLocations = new ArrayList<>();
        if (appPackagesFilePath != null && !appPackagesFilePath.trim().isEmpty()) {
            String dir = appPackagesFilePath.trim().replace('\\', '/');
            if (!dir.endsWith("/")) {
                dir += "/";
            }
            packageLocations.add("file:" + dir);
        }
        String userDir = System.getProperty("user.dir");
        if (userDir != null && !userDir.trim().isEmpty()) {
            String normUserDir = userDir.trim().replace('\\', '/');
            if (!normUserDir.endsWith("/")) {
                normUserDir += "/";
            }
            packageLocations.add("file:" + normUserDir + "upload/packages/");
        }

        if (!packageLocations.isEmpty()) {
            registry.addResourceHandler("/packages/**", "/admin/app/packages/**")
                    .addResourceLocations(packageLocations.toArray(new String[0]));
        }

        // 补充：放行Spring Boot默认静态资源目录（避免默认目录下的静态资源访问失败）
        registry.addResourceHandler("/**")
                .addResourceLocations("classpath:/META-INF/resources/")
                .addResourceLocations("classpath:/resources/")
                .addResourceLocations("classpath:/static/")
                .addResourceLocations("classpath:/public/");
    }
}
