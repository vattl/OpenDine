package com.lanf.printing.model;

import org.springframework.util.StringUtils;

import java.util.Arrays;
import java.util.Collections;
import java.util.List;

/**
 * 统一打印场景常量定义与归一化
 */
public final class PrintScenario {

    private PrintScenario() {}

    /** 厨房小票（后厨制作分单与档口出菜凭据） */
    public static final String KITCHEN = "kitchen";

    /** 前台整单（收银前台全单点菜单） */
    public static final String FULL_ORDER = "full_order";

    /** 预结单（顾客核对消费预结明细） */
    public static final String PRE_CHECKOUT = "pre_checkout";

    /** 结账单（结账完成打印正式小票凭证） */
    public static final String CHECKOUT = "checkout";

    /** 传菜单 / 催菜单（催菜/划单/传菜出餐凭条） */
    public static final String EXPEDITE = "expedite";

    /** 外卖单（外卖平台接单配送凭条） */
    public static final String TAKEOUT = "takeout";

    /** 打包单（到店自提/打包订单的独立核餐凭条） */
    public static final String PACKING = "packing";

    /** 通用点餐订单（兼容旧版别名） */
    public static final String ORDER = "order";

    /** KDS 传菜划单（兼容旧版别名） */
    public static final String SERVE = "serve";

    /** 收银交接班报表小票 */
    public static final String SHIFT = "shift";

    /** 订单退款小票 */
    public static final String REFUND = "refund";

    /** 商品/杯贴标签 */
    public static final String LABEL = "label";

    /** 设备自检与测试出票 */
    public static final String TEST = "test";

    /** 新增自定义场景时使用的小写机器码格式。 */
    private static final String CUSTOM_CODE_PATTERN = "[a-z][a-z0-9_-]{0,31}";

    /**
     * 将调用方传入的场景转为用于规则、流水和接口响应的标准小写码。
     * 未注册但符合机器码约束的值会保留，作为自定义场景使用。
     */
    public static String canonicalCode(String raw) {
        String s = StringUtils.hasText(raw) ? raw.trim().toLowerCase() : CHECKOUT;
        switch (s) {
            case "kitchen":
            case "kitchen_ticket": return KITCHEN;
            case "full_order": return FULL_ORDER;
            case "pre_checkout":
            case "precheckout": return PRE_CHECKOUT;
            case "checkout": return CHECKOUT;
            case "expedite":
            case "serve":
            case "kds_serve": return EXPEDITE;
            case "takeout":
            case "delivery": return TAKEOUT;
            case "packing":
            case "packing_slip":
            case "pickup": return PACKING;
            case "order":
            case "receipt":
            case "bill": return CHECKOUT;
            case "shift": return SHIFT;
            case "refund": return REFUND;
            case "label": return LABEL;
            case "test": return TEST;
            default:
                if (!s.matches(CUSTOM_CODE_PATTERN)) {
                    throw new IllegalArgumentException("场景编码仅支持 1-32 位小写字母开头，可包含数字、中划线、下划线");
                }
                return s;
        }
    }

    /**
     * 为旧 `order` 调用补齐实际单据语义；显式场景和自定义场景保持原有语义。
     */
    public static String resolveDispatchCode(String raw, PrintContext context) {
        String s = StringUtils.hasText(raw) ? raw.trim().toLowerCase() : "";
        if ("order".equals(s) || "receipt".equals(s) || "bill".equals(s)) {
            if (context != null && context.isAddDishes()) {
                return FULL_ORDER;
            }
            if (context != null && context.getOrder() != null
                    && "success".equalsIgnoreCase(context.getOrder().getTransac_status())) {
                return CHECKOUT;
            }
            return PRE_CHECKOUT;
        }
        return canonicalCode(raw);
    }

    /** 当前场景是否属于内置的十一类票据。 */
    public static boolean isBuiltIn(String raw) {
        String code = canonicalCode(raw);
        return Arrays.asList(KITCHEN, FULL_ORDER, PRE_CHECKOUT, CHECKOUT, EXPEDITE,
                TAKEOUT, PACKING, SHIFT, REFUND, LABEL, TEST).contains(code);
    }

    /**
     * 冷启动无规则门店是否允许使用默认设备兜底。
     * 打包单属于显式 opt-in 的独立票据，禁止因默认设备而自动开启。
     */
    public static boolean allowsUnconfiguredDeviceFallback(String raw) {
        return !PACKING.equals(canonicalCode(raw));
    }

    /**
     * 标准规则优先，旧别名仅在不存在标准规则时作为平滑迁移回退。
     */
    public static List<String> ruleLookupCodes(String raw) {
        String code = canonicalCode(raw);
        switch (code) {
            case CHECKOUT: return Arrays.asList(CHECKOUT, ORDER, "receipt", "bill");
            case EXPEDITE: return Arrays.asList(EXPEDITE, SERVE, "kds_serve");
            case KITCHEN: return Arrays.asList(KITCHEN, "kitchen_ticket");
            case PRE_CHECKOUT: return Arrays.asList(PRE_CHECKOUT, ORDER, CHECKOUT);
            case FULL_ORDER: return Arrays.asList(code, ORDER);
            default: return Collections.singletonList(code);
        }
    }

    /** 场景中文名；自定义场景回显其标准机器码。 */
    public static String displayName(String raw) {
        String code = canonicalCode(raw);
        switch (code) {
            case KITCHEN: return "厨房小票";
            case FULL_ORDER: return "前台整单";
            case PRE_CHECKOUT: return "预结单";
            case CHECKOUT: return "结账单";
            case EXPEDITE: return "传菜单";
            case TAKEOUT: return "外卖单";
            case PACKING: return "打包单";
            case SHIFT: return "收银交接班报表";
            case REFUND: return "退款单据";
            case LABEL: return "商品标签/杯贴";
            case TEST: return "自检测试单";
            default: return "自定义场景(" + code + ")";
        }
    }

    /**
     * 将不同写法归一化为大写标准场景名（用于模板库匹配）
     */
    public static String normalizeScenario(String raw) {
        return canonicalCode(raw).toUpperCase();
    }

    /**
     * 场景展示中文名称
     */
    public static String getScenarioDisplayName(String raw) {
        return displayName(raw);
    }
}
