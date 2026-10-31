package com.lanf.printing.model;

import java.io.Serializable;
import java.util.ArrayList;
import java.util.List;
import java.util.Map;

/**
 * 打印小票预览响应数据模型
 */
public class PrintPreviewResult implements Serializable {
    private static final long serialVersionUID = 1L;

    /** 业务场景代码 (ORDER / KITCHEN / SERVE / REFUND / SHIFT / LABEL / TEST) */
    private String scenario;
    /** 场景中文名称 */
    private String scenarioName;
    /** 纸张规格 (58mm / 80mm) */
    private String paperSize;
    /** 纸张宽度 (毫米数: 58 / 80) */
    private int paperWidthMm;
    /** 纸张单行字符数 (32 / 48) */
    private int paperWidthChars;
    /** 门店名称 */
    private String shopName;
    /** 小票总张数 (后厨分单拆单场景可能返回多张) */
    private int totalTickets;
    /** 小票列表 */
    private List<TicketPreviewItem> tickets = new ArrayList<>();
    /** 合并的原生指令文本 */
    private String rawCombinedContent;
    /** 渲染时间戳 (ISO-8601) */
    private String renderedAt;
    /** 使用真实上下文时未能绑定而隐藏的字段行。 */
    private List<String> bindingWarnings = new ArrayList<>();
    /** 目标设备不支持的原生指令。 */
    private List<String> capabilityWarnings = new ArrayList<>();

    public PrintPreviewResult() {}

    public String getScenario() { return scenario; }
    public void setScenario(String scenario) { this.scenario = scenario; }

    public String getScenarioName() { return scenarioName; }
    public void setScenarioName(String scenarioName) { this.scenarioName = scenarioName; }

    public String getPaperSize() { return paperSize; }
    public void setPaperSize(String paperSize) { this.paperSize = paperSize; }

    public int getPaperWidthMm() { return paperWidthMm; }
    public void setPaperWidthMm(int paperWidthMm) { this.paperWidthMm = paperWidthMm; }

    public int getPaperWidthChars() { return paperWidthChars; }
    public void setPaperWidthChars(int paperWidthChars) { this.paperWidthChars = paperWidthChars; }

    public String getShopName() { return shopName; }
    public void setShopName(String shopName) { this.shopName = shopName; }

    public int getTotalTickets() { return totalTickets; }
    public void setTotalTickets(int totalTickets) { this.totalTickets = totalTickets; }

    public List<TicketPreviewItem> getTickets() { return tickets; }
    public void setTickets(List<TicketPreviewItem> tickets) {
        this.tickets = tickets;
        this.totalTickets = tickets != null ? tickets.size() : 0;
    }

    public String getRawCombinedContent() { return rawCombinedContent; }
    public void setRawCombinedContent(String rawCombinedContent) { this.rawCombinedContent = rawCombinedContent; }

    public String getRenderedAt() { return renderedAt; }
    public void setRenderedAt(String renderedAt) { this.renderedAt = renderedAt; }
    public List<String> getBindingWarnings() { return bindingWarnings; }
    public void setBindingWarnings(List<String> bindingWarnings) { this.bindingWarnings = bindingWarnings != null ? bindingWarnings : new ArrayList<>(); }
    public List<String> getCapabilityWarnings() { return capabilityWarnings; }
    public void setCapabilityWarnings(List<String> capabilityWarnings) { this.capabilityWarnings = capabilityWarnings != null ? capabilityWarnings : new ArrayList<>(); }

    /**
     * 单张小票预览数据
     */
    public static class TicketPreviewItem implements Serializable {
        private static final long serialVersionUID = 1L;

        /** 小票序号 (0, 1, 2...) */
        private int ticketIndex;
        /** 小票标题 (如 "结账单", "后厨制作单[凉菜类]") */
        private String title;
        /** 原生打印指令内容 (包含 <CB>, <BR>, <C> 等标签) */
        private String rawContent;
        /** 去除标签后的排版纯文本 (可直接用于 <pre> 展示) */
        private String plainText;
        /** 结构化可视化节点树 (前端可遍历直接渲染高保真 UI) */
        private List<PrintPreviewElement> elements = new ArrayList<>();
        private Long ruleId;
        private Long deviceId;
        private String deviceName;
        private Long templateId;
        private String templateCode;

        public TicketPreviewItem() {}

        public TicketPreviewItem(int ticketIndex, String title, String rawContent, String plainText, List<PrintPreviewElement> elements) {
            this.ticketIndex = ticketIndex;
            this.title = title;
            this.rawContent = rawContent;
            this.plainText = plainText;
            this.elements = elements != null ? elements : new ArrayList<>();
        }

        public int getTicketIndex() { return ticketIndex; }
        public void setTicketIndex(int ticketIndex) { this.ticketIndex = ticketIndex; }

        public String getTitle() { return title; }
        public void setTitle(String title) { this.title = title; }

        public String getRawContent() { return rawContent; }
        public void setRawContent(String rawContent) { this.rawContent = rawContent; }

        public String getPlainText() { return plainText; }
        public void setPlainText(String plainText) { this.plainText = plainText; }

        public List<PrintPreviewElement> getElements() { return elements; }
        public void setElements(List<PrintPreviewElement> elements) { this.elements = elements; }
        public Long getRuleId() { return ruleId; }
        public void setRuleId(Long ruleId) { this.ruleId = ruleId; }
        public Long getDeviceId() { return deviceId; }
        public void setDeviceId(Long deviceId) { this.deviceId = deviceId; }
        public String getDeviceName() { return deviceName; }
        public void setDeviceName(String deviceName) { this.deviceName = deviceName; }
        public Long getTemplateId() { return templateId; }
        public void setTemplateId(Long templateId) { this.templateId = templateId; }
        public String getTemplateCode() { return templateCode; }
        public void setTemplateCode(String templateCode) { this.templateCode = templateCode; }
    }

    /**
     * 结构化小票元素
     */
    public static class PrintPreviewElement implements Serializable {
        private static final long serialVersionUID = 1L;

        /** 元素类型: HEADER, TEXT, DIVIDER, TABLE_HEADER, TABLE_ROW, KEY_VALUE, QRCODE, BARCODE, CUT */
        private String type;
        /** 文本内容 */
        private String text;
        /** 对齐方式: LEFT, CENTER, RIGHT */
        private String align = "LEFT";
        /** 是否加粗 */
        private boolean bold;
        /** 字号: NORMAL, DOUBLE, LARGE */
        private String size = "NORMAL";
        /** 键值对 Key (用于 KEY_VALUE 类型) */
        private String key;
        /** 键值对 Value (用于 KEY_VALUE 类型) */
        private String value;
        /** 表格列数据 (用于 TABLE_HEADER / TABLE_ROW) */
        private List<String> columns;
        /** 附加元数据 (如 qrCodeUrl, barcodeNumber 等) */
        private Map<String, Object> meta;

        public PrintPreviewElement() {}

        public PrintPreviewElement(String type, String text) {
            this.type = type;
            this.text = text;
        }

        public static PrintPreviewElement text(String text, String align, boolean bold, String size) {
            PrintPreviewElement el = new PrintPreviewElement("TEXT", text);
            el.setAlign(align != null ? align : "LEFT");
            el.setBold(bold);
            el.setSize(size != null ? size : "NORMAL");
            return el;
        }

        public static PrintPreviewElement header(String text, String align, boolean bold, String size) {
            PrintPreviewElement el = new PrintPreviewElement("HEADER", text);
            el.setAlign(align != null ? align : "CENTER");
            el.setBold(bold);
            el.setSize(size != null ? size : "DOUBLE");
            return el;
        }

        public static PrintPreviewElement divider(String text) {
            PrintPreviewElement el = new PrintPreviewElement("DIVIDER", text);
            el.setAlign("CENTER");
            return el;
        }

        public static PrintPreviewElement tableHeader(List<String> cols) {
            PrintPreviewElement el = new PrintPreviewElement("TABLE_HEADER", null);
            el.setColumns(cols);
            return el;
        }

        public static PrintPreviewElement tableRow(List<String> cols) {
            PrintPreviewElement el = new PrintPreviewElement("TABLE_ROW", null);
            el.setColumns(cols);
            return el;
        }

        public static PrintPreviewElement keyValue(String key, String value, boolean bold, String size, String align) {
            PrintPreviewElement el = new PrintPreviewElement("KEY_VALUE", null);
            el.setKey(key);
            el.setValue(value);
            el.setBold(bold);
            el.setSize(size != null ? size : "NORMAL");
            el.setAlign(align != null ? align : "LEFT");
            return el;
        }

        public static PrintPreviewElement cut() {
            return new PrintPreviewElement("CUT", null);
        }

        public String getType() { return type; }
        public void setType(String type) { this.type = type; }

        public String getText() { return text; }
        public void setText(String text) { this.text = text; }

        public String getAlign() { return align; }
        public void setAlign(String align) { this.align = align; }

        public boolean isBold() { return bold; }
        public void setBold(boolean bold) { this.bold = bold; }

        public String getSize() { return size; }
        public void setSize(String size) { this.size = size; }

        public String getKey() { return key; }
        public void setKey(String key) { this.key = key; }

        public String getValue() { return value; }
        public void setValue(String value) { this.value = value; }

        public List<String> getColumns() { return columns; }
        public void setColumns(List<String> columns) { this.columns = columns; }

        public Map<String, Object> getMeta() { return meta; }
        public void setMeta(Map<String, Object> meta) { this.meta = meta; }
    }
}
