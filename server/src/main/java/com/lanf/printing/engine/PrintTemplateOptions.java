package com.lanf.printing.engine;

import lombok.Data;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

/**
 * 打印模板渲染选项
 */
@Data
public class PrintTemplateOptions {

    /** 纸张规格：58mm / 80mm */
    private String paperWidth = "58mm";

    /** 是否附带二维码 */
    private boolean showQrCode = true;

    /** 二维码 URL */
    private String qrCodeUrl = "https://u.wechat.com/EF9MZwaAbHhL79QCtBgAVAA?s=2";

    /** 品牌或店铺标头 */
    private String brandHeader = "老肥油边王";

    /** 是否自动切刀 */
    private boolean autoCut = true;

    /** 蜂鸣器提示 */
    private boolean beeper = true;

    /** 是否为加菜单（加菜场景） */
    private Boolean isAddDish;

    /** 由真实业务上下文填充的变量，模板引擎绝不再生成样例值。 */
    private Map<String, Object> bindings = new LinkedHashMap<>();
    /** 缺失绑定导致隐藏的文本行。 */
    private List<String> bindingWarnings = new ArrayList<>();
    /** 当前设备不具备的原生能力。 */
    private List<String> capabilityWarnings = new ArrayList<>();

    public static PrintTemplateOptions defaultOptions() {
        return new PrintTemplateOptions();
    }
}
