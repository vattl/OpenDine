package com.lanf.order;

import org.springframework.util.StringUtils;

import java.util.Locale;

/**
 * 退菜时的库存变动动作模式。
 */
public enum RefundStockAction {

    /**
     * 回退库存（默认）：将退菜数量加回门店库存，若原为售罄且加回后 stock > 0 则自动解除售罄。
     */
    RESTORE,

    /**
     * 损耗 / 报废：菜品已制作或食材已损耗，仅退菜/退款，不将数量加回库存。
     */
    NO_RESTORE,

    /**
     * 缺货 / 估清：因后厨食材用尽而退菜，不回退库存，并将当前门店该菜品库存清零（stock=0）且强制标记售罄（sold_out=1），同时下发 WebSocket 售罄广播。
     */
    OUT_OF_STOCK;

    /**
     * 从字符串安全解析枚举值，不区分大小写，支持常见别名映射。
     * 若未传或解析失败，返回传入的默认值。
     *
     * @param raw 原始字符串（如 "RESTORE", "NO_RESTORE", "OUT_OF_STOCK", "waste", "sold_out" 等）
     * @param defaultVal 默认值（通常为 RESTORE）
     * @return 解析后的 RefundStockAction
     */
    public static RefundStockAction from(String raw, RefundStockAction defaultVal) {
        if (!StringUtils.hasText(raw)) {
            return defaultVal;
        }
        String normalized = raw.trim().toUpperCase(Locale.ROOT);
        switch (normalized) {
            case "RESTORE":
            case "RETURN":
            case "REVERT":
                return RESTORE;
            case "NO_RESTORE":
            case "NORESTORE":
            case "WASTE":
            case "SPOIL":
            case "NONE":
                return NO_RESTORE;
            case "OUT_OF_STOCK":
            case "OUTOFSTOCK":
            case "SOLD_OUT":
            case "SOLDOUT":
            case "LACK":
                return OUT_OF_STOCK;
            default:
                try {
                    return RefundStockAction.valueOf(normalized);
                } catch (IllegalArgumentException e) {
                    return defaultVal;
                }
        }
    }
}
