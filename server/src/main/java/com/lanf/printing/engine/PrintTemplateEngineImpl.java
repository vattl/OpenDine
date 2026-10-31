package com.lanf.printing.engine;

import com.baomidou.mybatisplus.core.conditions.query.QueryWrapper;
import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.lanf.entity.Category;
import com.lanf.entity.Order;
import com.lanf.entity.OrderDetail;
import com.lanf.entity.Shift;
import com.lanf.entity.Shop;
import com.lanf.entity.TakeoutDelivery;
import com.lanf.payment.support.PaymentDiningTypeUtil;
import com.lanf.util.OrderPackagingFeeCalculator;
import com.lanf.printing.model.PrintScenario;
import com.lanf.printing.model.PrintTemplateDsl;
import com.lanf.service.ICategoryService;
import com.lanf.service.IShopService;
import com.lanf.service.ITakeoutDeliveryService;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Component;
import org.springframework.util.StringUtils;

import java.text.SimpleDateFormat;
import java.time.LocalDateTime;
import java.time.format.DateTimeFormatter;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.Collections;
import java.util.Date;
import java.util.HashMap;
import java.util.HashSet;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Set;

/**
 * 统一小票模板渲染引擎实现类（完全基于数据库 DSL 动态解释渲染）
 */
@Component
public class PrintTemplateEngineImpl implements PrintTemplateEngine {

    private static final Logger log = LoggerFactory.getLogger(PrintTemplateEngineImpl.class);
    private static final String TIME_FORMAT_DISPLAY = "yyyy-MM-dd HH:mm:ss";
    private static final DateTimeFormatter DATETIME_FMT = DateTimeFormatter.ofPattern("yyyy-MM-dd HH:mm:ss");
    private static final ObjectMapper SPEC_MAPPER = new ObjectMapper();

    /** 默认合并出票的后厨分类列表（老肥特色/烤串类等） */
    private static final Set<String> DEFAULT_MERGED_KITCHEN_CIDS = Collections.unmodifiableSet(
            new HashSet<>(Arrays.asList("1", "2", "3"))
    );

    @Autowired(required = false)
    private IShopService shopService;

    @Autowired(required = false)
    private ICategoryService categoryService;

    @Autowired(required = false)
    private ITakeoutDeliveryService takeoutDeliveryService;

    @Override
    public String renderReceiptTicket(Order order, boolean isAddDishes, PrintTemplateOptions options) {
        String scenario = isAddDishes ? PrintScenario.FULL_ORDER : (order != null && "success".equalsIgnoreCase(order.getTransac_status()) ? PrintScenario.CHECKOUT : PrintScenario.PRE_CHECKOUT);
        String paperSize = options != null && StringUtils.hasText(options.getPaperWidth()) ? options.getPaperWidth() : "58mm";
        PrintTemplateDsl dsl = buildDefaultDsl(scenario, paperSize);
        return renderDynamicTicket(order, dsl, options);
    }

    @Override
    public List<String> renderKitchenTickets(Order order, Set<String> cidFilter, PrintTemplateOptions options) {
        String paperSize = options != null && StringUtils.hasText(options.getPaperWidth()) ? options.getPaperWidth() : "58mm";
        PrintTemplateDsl dsl = buildDefaultDsl(PrintScenario.KITCHEN, paperSize);
        return renderDynamicKitchenTickets(order, dsl, cidFilter, options);
    }

    @Override
    public String renderServeTicket(Order order, OrderDetail detail, int serveQty, PrintTemplateOptions options) {
        String paperSize = options != null && StringUtils.hasText(options.getPaperWidth()) ? options.getPaperWidth() : "58mm";
        PrintTemplateDsl dsl = buildDefaultDsl(PrintScenario.EXPEDITE, paperSize);
        return renderDynamicServeTicket(order, detail, serveQty, dsl, options);
    }

    @Override
    public String renderShiftTicket(Shift shift, Map<String, Object> statistics, PrintTemplateOptions options) {
        String paperSize = options != null && StringUtils.hasText(options.getPaperWidth()) ? options.getPaperWidth() : "58mm";
        PrintTemplateDsl dsl = buildDefaultDsl(PrintScenario.SHIFT, paperSize);
        return renderDynamicShiftTicket(shift, dsl, statistics, options);
    }

    @Override
    public String renderRefundTicket(Order order, Map<String, Object> refundInfo, PrintTemplateOptions options) {
        String paperSize = options != null && StringUtils.hasText(options.getPaperWidth()) ? options.getPaperWidth() : "58mm";
        PrintTemplateDsl dsl = buildDefaultDsl(PrintScenario.REFUND, paperSize);
        return renderDynamicRefundTicket(order, dsl, refundInfo, options);
    }

    @Override
    public String renderLabelTicket(Order order, OrderDetail detail, PrintTemplateOptions options) {
        String paperSize = options != null && StringUtils.hasText(options.getPaperWidth()) ? options.getPaperWidth() : "58mm";
        PrintTemplateDsl dsl = buildDefaultDsl(PrintScenario.LABEL, paperSize);
        return renderDynamicLabelTicket(order, detail, dsl, options);
    }

    @Override
    public String renderTestTicket(String testType, String deviceName, String transport, String brand, int shopId) {
        PrintTemplateDsl dsl = buildDefaultDsl(PrintScenario.TEST, "58mm");
        return renderDynamicTestTicket(dsl, testType, deviceName, transport, brand, shopId);
    }

    // =========================================================================
    // 基于 DSL 动态解释渲染实现
    // =========================================================================

    @Override
    public String renderDynamicTicket(Order order, PrintTemplateDsl dsl, PrintTemplateOptions options) {
        if (dsl == null) {
            return "";
        }

        if ("TEXT".equalsIgnoreCase(dsl.getMode()) && StringUtils.hasText(dsl.getRawTemplate())) {
            return renderRawTextTemplate(order, dsl, options);
        }

        if (dsl.getBlocks() == null || dsl.getBlocks().isEmpty()) {
            if (StringUtils.hasText(dsl.getRawTemplate())) {
                return renderRawTextTemplate(order, dsl, options);
            }
            return "";
        }

        StringBuilder content = new StringBuilder();
        List<OrderDetail> goodsList = order != null && order.getGoods_list() != null ? order.getGoods_list() : Collections.emptyList();

        for (PrintTemplateDsl.TemplateBlock block : dsl.getBlocks()) {
            if (block == null || (block.getEnabled() != null && !block.getEnabled())) {
                continue;
            }
            String type = block.getType() != null ? block.getType().toUpperCase() : "";
            Map<String, Object> cfg = block.getConfig() != null ? block.getConfig() : Collections.emptyMap();

            int linesBefore = parsePositiveInt(cfg.get("linesBefore"), parsePositiveInt(cfg.get("blankLinesBefore"), 0));
            for (int i = 0; i < linesBefore; i++) {
                content.append("<BR>");
            }

            switch (type) {
                case "HEADER":
                    renderDynamicHeader(content, order, cfg, options);
                    break;
                case "ORDER_INFO":
                    renderDynamicOrderInfo(content, order, cfg);
                    break;
                case "DISH_ITEMS":
                    renderDynamicDishItems(content, goodsList, cfg, dsl.getPaperSize());
                    break;
                case "PAYMENT_SUMMARY":
                    renderDynamicPaymentSummary(content, order, cfg, dsl.getPaperSize());
                    break;
                case "MEMBER_INFO":
                    renderDynamicMemberInfo(content, order, cfg);
                    break;
                case "DELIVERY_INFO":
                    renderDynamicDeliveryInfo(content, order, cfg);
                    break;
                case "REMARK":
                    renderDynamicRemark(content, order, cfg);
                    break;
                case "CUSTOM_TEXT":
                    renderDynamicCustomText(content, order, cfg);
                    break;
                case "DIVIDER":
                    renderDynamicDivider(content, cfg, dsl.getPaperSize());
                    break;
                case "SPACING":
                    int spacingLines = parsePositiveInt(cfg.get("lines"), 1);
                    for (int s = 0; s < spacingLines; s++) {
                        content.append("<BR>");
                    }
                    break;
                case "QRCODE":
                    renderDynamicQrCode(content, cfg, options);
                    break;
                case "LOGO":
                    content.append("<LOGO><BR>");
                    break;
                case "PLUGIN":
                case "CASH_DRAWER":
                    content.append("<PLUGIN>");
                    break;
                case "CUT":
                case "CUT_PAPER":
                    content.append("<CUT>");
                    break;
                case "BARCODE":
                    renderBarcode(content, cfg, order, options);
                    break;
                case "FOOTER":
                    renderDynamicFooter(content, cfg, options);
                    break;
                default:
                    break;
            }

            int linesAfter = parsePositiveInt(cfg.get("linesAfter"), parsePositiveInt(cfg.get("blankLinesAfter"), 0));
            for (int i = 0; i < linesAfter; i++) {
                content.append("<BR>");
            }
        }

        int feedLines = dsl.getFeedLines() != null && dsl.getFeedLines() > 0 ? dsl.getFeedLines() : 2;
        for (int i = 0; i < feedLines; i++) {
            content.append("<BR>");
        }
        appendAudio(content, dsl);
        if (Boolean.TRUE.equals(dsl.getAutoCut()) && content.indexOf("<CUT>") < 0) {
            content.append("<CUT>");
        }
        return content.toString();
    }

    @Override
    public List<String> renderDynamicKitchenTickets(Order order, PrintTemplateDsl dsl, Set<String> cidFilter, PrintTemplateOptions options) {
        if (dsl == null) {
            return Collections.emptyList();
        }
        if (dsl.getBlocks() == null || dsl.getBlocks().isEmpty()) {
            // TEXT/rawTemplate 模式：读取 JSON 中的 rawTemplate 解析组装（无 cid 分组能力，整单出票）
            if (StringUtils.hasText(dsl.getRawTemplate())) {
                return Collections.singletonList(renderDynamicTicket(order, dsl, options));
            }
            return Collections.emptyList();
        }
        if (cidFilter == null || cidFilter.isEmpty()) {
            return Collections.singletonList(renderDynamicTicket(order, dsl, options));
        }

        List<OrderDetail> allGoods = order != null && order.getGoods_list() != null ? order.getGoods_list() : Collections.emptyList();
        Map<String, List<OrderDetail>> byCid = new LinkedHashMap<>();
        for (OrderDetail d : allGoods) {
            String cid = d.getCid() != null ? d.getCid() : "default";
            if (cidFilter.contains(cid) || cidFilter.contains("*")) {
                byCid.computeIfAbsent(cid, k -> new ArrayList<>()).add(d);
            }
        }

        List<String> results = new ArrayList<>();
        for (Map.Entry<String, List<OrderDetail>> entry : byCid.entrySet()) {
            Order subOrder = copyOrderWithGoods(order, entry.getValue());
            results.add(renderDynamicTicket(subOrder, dsl, options));
        }
        return results.isEmpty() ? Collections.singletonList(renderDynamicTicket(order, dsl, options)) : results;
    }

    @Override
    public String renderDynamicServeTicket(Order order, OrderDetail detail, int serveQty, PrintTemplateDsl dsl, PrintTemplateOptions options) {
        if (dsl == null) {
            return "";
        }
        List<OrderDetail> singleGood = new ArrayList<>();
        if (detail != null) {
            OrderDetail copy = new OrderDetail();
            copy.setName(detail.getName());
            copy.setSelectedSpicy(detail.getSelectedSpicy());
            copy.setQuantity(String.valueOf(serveQty > 0 ? serveQty : 1));
            copy.setUnit(detail.getUnit());
            copy.setTotal_price(detail.getTotal_price());
            singleGood.add(copy);
        }
        Order subOrder = copyOrderWithGoods(order, singleGood);
        return renderDynamicTicket(subOrder, dsl, options);
    }

    @Override
    public String renderDynamicShiftTicket(Shift shift, PrintTemplateDsl dsl, Map<String, Object> stats, PrintTemplateOptions options) {
        if (dsl == null) {
            return "";
        }
        if (("TEXT".equalsIgnoreCase(dsl.getMode()) || dsl.getBlocks() == null || dsl.getBlocks().isEmpty())
                && StringUtils.hasText(dsl.getRawTemplate())) {
            return renderRawShiftTemplate(shift, dsl, stats, options);
        }
        StringBuilder sb = new StringBuilder();
        SimpleDateFormat sdf = new SimpleDateFormat(TIME_FORMAT_DISPLAY);

        for (PrintTemplateDsl.TemplateBlock block : dsl.getBlocks()) {
            if (block == null || (block.getEnabled() != null && !block.getEnabled())) continue;
            String type = block.getType() != null ? block.getType().toUpperCase() : "";
            Map<String, Object> cfg = block.getConfig() != null ? block.getConfig() : Collections.emptyMap();

            switch (type) {
                case "HEADER":
                    String headerTitle = cfg.get("customTitle") != null ? String.valueOf(cfg.get("customTitle")) : "收银交接班报表";
                    String align = String.valueOf(cfg.getOrDefault("align", "CENTER"));
                    String size = String.valueOf(cfg.getOrDefault("size", "DOUBLE"));
                    boolean bold = !Boolean.FALSE.equals(cfg.get("bold"));
                    wrapStyledLine(sb, interpolateShiftVariables(headerTitle, shift, stats), align, size, bold);
                    if (cfg.get("subTitle") != null && StringUtils.hasText(String.valueOf(cfg.get("subTitle")))) {
                        wrapStyledLine(sb, interpolateShiftVariables(String.valueOf(cfg.get("subTitle")), shift, stats), align, "NORMAL", true);
                    }
                    break;
                case "DIVIDER":
                    renderDynamicDivider(sb, cfg, dsl.getPaperSize());
                    break;
                case "CUSTOM_TEXT":
                    String customContent = cfg.get("content") != null ? String.valueOf(cfg.get("content")) : null;
                    if (StringUtils.hasText(customContent)) {
                        String text = interpolateShiftVariables(customContent, shift, stats);
                        String tAlign = String.valueOf(cfg.getOrDefault("align", "LEFT"));
                        String tSize = String.valueOf(cfg.getOrDefault("size", "NORMAL"));
                        boolean tBold = Boolean.TRUE.equals(cfg.get("bold"));
                        wrapStyledLine(sb, text, tAlign, tSize, tBold);
                    } else {
                        // 默认交接班明细
                        if (shift != null) {
                            sb.append("班次 ID: #").append(shift.getId()).append("<BR>");
                            sb.append("门店 ID: #").append(shift.getShop_id()).append("<BR>");
                            sb.append("收银员 ID: #").append(shift.getAdmin_id()).append("<BR>");
                            if (shift.getStart_time() != null) {
                                sb.append("开班时间: ").append(sdf.format(shift.getStart_time())).append("<BR>");
                            }
                            if (shift.getEnd_time() != null) {
                                sb.append("交班时间: ").append(sdf.format(shift.getEnd_time())).append("<BR>");
                            }
                            sb.append("备用金: ¥").append(shift.getStart_cash() != null ? String.format("%.2f", shift.getStart_cash().doubleValue()) : "0.00").append("<BR>");
                            sb.append("总单数: ").append(shift.getOrder_count() != null ? shift.getOrder_count() : 0).append(" 单<BR>");
                            sb.append("<B>实收总额: ¥").append(shift.getTotal_amount() != null ? String.format("%.2f", shift.getTotal_amount().doubleValue()) : "0.00").append("</B><BR>");
                        }
                        if (stats != null && !stats.isEmpty()) {
                            sb.append(buildDividerLine(dsl != null ? dsl.getPaperSize() : "58mm", null)).append("<BR>");
                            sb.append("<B>渠道收款明细:</B><BR>");
                            for (Map.Entry<String, Object> entry : stats.entrySet()) {
                                sb.append(entry.getKey()).append(": ").append(entry.getValue()).append("<BR>");
                            }
                        }
                        sb.append("打印时间: ").append(LocalDateTime.now().format(DATETIME_FMT)).append("<BR>");
                    }
                    break;
                case "QRCODE":
                    renderDynamicQrCode(sb, cfg, options);
                    break;
                case "FOOTER":
                    String footerText = cfg.get("thankText") != null ? String.valueOf(cfg.get("thankText")) : "交接班核对无误请签字确认";
                    wrapStyledLine(sb, interpolateShiftVariables(footerText, shift, stats), "CENTER", "NORMAL", false);
                    break;
                default:
                    break;
            }
        }
        sb.append("<BR><BR>");
        if (Boolean.TRUE.equals(dsl.getAutoCut())) {
            sb.append("<CUT>");
        }
        return sb.toString();
    }

    private String interpolateShiftVariables(String text, Shift shift, Map<String, Object> stats) {
        if (!StringUtils.hasText(text)) return "";
        String res = text;
        SimpleDateFormat sdf = new SimpleDateFormat(TIME_FORMAT_DISPLAY);
        if (shift != null) {
            String shiftId = shift.getId() != null ? String.valueOf(shift.getId()) : "0";
            res = res.replace("{shiftId}", shiftId).replace("{班次}", shiftId).replace("{班次ID}", shiftId);
            String shopId = shift.getShop_id() != null ? String.valueOf(shift.getShop_id()) : "1";
            res = res.replace("{shopId}", shopId).replace("{门店ID}", shopId).replace("{门店编号}", shopId);
            String adminId = shift.getAdmin_id() != null ? String.valueOf(shift.getAdmin_id()) : "1";
            res = res.replace("{adminId}", adminId).replace("{收银员}", adminId).replace("{收银员ID}", adminId);
            String startTime = shift.getStart_time() != null ? sdf.format(shift.getStart_time()) : "";
            res = res.replace("{startTime}", startTime).replace("{开班时间}", startTime);
            String endTime = shift.getEnd_time() != null ? sdf.format(shift.getEnd_time()) : sdf.format(new Date());
            res = res.replace("{endTime}", endTime).replace("{交班时间}", endTime);
            String startCash = shift.getStart_cash() != null ? String.format("%.2f", shift.getStart_cash().doubleValue()) : "0.00";
            res = res.replace("{startCash}", startCash).replace("{备用金}", startCash);
            String orderCount = shift.getOrder_count() != null ? String.valueOf(shift.getOrder_count()) : "0";
            res = res.replace("{orderCount}", orderCount).replace("{总单数}", orderCount).replace("{单数}", orderCount);
            String totalAmount = shift.getTotal_amount() != null ? String.format("%.2f", shift.getTotal_amount().doubleValue()) : "0.00";
            res = res.replace("{totalAmount}", totalAmount).replace("{实收总额}", totalAmount).replace("{营业额}", totalAmount);
        }
        if (stats != null) {
            for (Map.Entry<String, Object> entry : stats.entrySet()) {
                String val = entry.getValue() != null ? String.valueOf(entry.getValue()) : "";
                res = res.replace("{" + entry.getKey() + "}", val);
            }
        }
        res = res.replace("{printTime}", LocalDateTime.now().format(DATETIME_FMT))
                 .replace("{打印时间}", LocalDateTime.now().format(DATETIME_FMT))
                 .replace("{time}", LocalDateTime.now().format(DATETIME_FMT));
        return res;
    }

    @Override
    public String renderDynamicRefundTicket(Order order, PrintTemplateDsl dsl, Map<String, Object> refundInfo, PrintTemplateOptions options) {
        if (dsl == null) {
            return "";
        }
        if (("TEXT".equalsIgnoreCase(dsl.getMode()) || dsl.getBlocks() == null || dsl.getBlocks().isEmpty())
                && StringUtils.hasText(dsl.getRawTemplate())) {
            return renderRawRefundTemplate(order, dsl, refundInfo, options);
        }
        StringBuilder sb = new StringBuilder();

        for (PrintTemplateDsl.TemplateBlock block : dsl.getBlocks()) {
            if (block == null || (block.getEnabled() != null && !block.getEnabled())) continue;
            String type = block.getType() != null ? block.getType().toUpperCase() : "";
            Map<String, Object> cfg = block.getConfig() != null ? block.getConfig() : Collections.emptyMap();

            switch (type) {
                case "HEADER":
                    String customTitle = cfg.get("customTitle") != null ? String.valueOf(cfg.get("customTitle")) : "退款单据";
                    String align = String.valueOf(cfg.getOrDefault("align", "CENTER"));
                    String size = String.valueOf(cfg.getOrDefault("size", "DOUBLE"));
                    boolean bold = !Boolean.FALSE.equals(cfg.get("bold"));
                    wrapStyledLine(sb, interpolateRefundVariables(customTitle, order, refundInfo), align, size, bold);
                    if (cfg.get("subTitle") != null && StringUtils.hasText(String.valueOf(cfg.get("subTitle")))) {
                        wrapStyledLine(sb, interpolateRefundVariables(String.valueOf(cfg.get("subTitle")), order, refundInfo), align, "NORMAL", true);
                    }
                    break;
                case "DIVIDER":
                    renderDynamicDivider(sb, cfg, dsl.getPaperSize());
                    break;
                case "ORDER_INFO":
                case "CUSTOM_TEXT":
                    String customContent = cfg.get("content") != null ? String.valueOf(cfg.get("content")) : null;
                    if (StringUtils.hasText(customContent)) {
                        String text = interpolateRefundVariables(customContent, order, refundInfo);
                        wrapStyledLine(sb, text, "LEFT", "NORMAL", false);
                    } else {
                        if (order != null) {
                            sb.append("原订单号: ").append(order.getOrder_no() != null ? order.getOrder_no() : "").append("<BR>");
                            String refundTable = order.getTable_number();
                            if (!StringUtils.hasText(refundTable) && isTakeoutOrder(order)) {
                                refundTable = "外卖";
                            }
                            sb.append("桌号: ").append(refundTable != null ? refundTable : "").append("<BR>");
                        }
                        if (refundInfo != null) {
                            if (refundInfo.get("refundAmount") != null) {
                                sb.append("<B>退款金额: ¥").append(refundInfo.get("refundAmount")).append("</B><BR>");
                            }
                            if (refundInfo.get("reason") != null) {
                                sb.append("退款原因: ").append(refundInfo.get("reason")).append("<BR>");
                            }
                            if (refundInfo.get("operator") != null) {
                                sb.append("操作人员: ").append(refundInfo.get("operator")).append("<BR>");
                            }
                        }
                        sb.append("退款时间: ").append(LocalDateTime.now().format(DATETIME_FMT)).append("<BR>");
                    }
                    break;
                case "QRCODE":
                    renderDynamicQrCode(sb, cfg, options);
                    break;
                case "FOOTER":
                    String thankText = cfg.get("thankText") != null ? String.valueOf(cfg.get("thankText")) : "**请妥善保管退款凭证**";
                    wrapStyledLine(sb, interpolateRefundVariables(thankText, order, refundInfo), "CENTER", "NORMAL", false);
                    break;
                default:
                    break;
            }
        }
        sb.append("<BR><BR>");
        if (Boolean.TRUE.equals(dsl.getAutoCut())) {
            sb.append("<CUT>");
        }
        return sb.toString();
    }

    private String interpolateRefundVariables(String text, Order order, Map<String, Object> refundInfo) {
        if (!StringUtils.hasText(text)) return "";
        String res = text;
        if (order != null) {
            String orderNo = order.getOrder_no() != null ? order.getOrder_no() : "";
            res = res.replace("{orderNo}", orderNo).replace("{原订单号}", orderNo).replace("{订单号}", orderNo);
            String tableNo = order.getTable_number() != null ? order.getTable_number() : "";
            res = res.replace("{tableNo}", tableNo).replace("{桌号}", tableNo).replace("{桌台号}", tableNo);
        }
        if (refundInfo != null) {
            String refundAmount = refundInfo.get("refundAmount") != null ? String.valueOf(refundInfo.get("refundAmount")) : "0.00";
            res = res.replace("{refundAmount}", refundAmount).replace("{退款金额}", refundAmount);
            String reason = refundInfo.get("reason") != null ? String.valueOf(refundInfo.get("reason")) : "";
            res = res.replace("{reason}", reason).replace("{退款原因}", reason);
            String operator = refundInfo.get("operator") != null ? String.valueOf(refundInfo.get("operator")) : "";
            res = res.replace("{operator}", operator).replace("{操作员}", operator).replace("{操作人员}", operator);
        }
        res = res.replace("{refundTime}", LocalDateTime.now().format(DATETIME_FMT))
                 .replace("{退款时间}", LocalDateTime.now().format(DATETIME_FMT))
                 .replace("{time}", LocalDateTime.now().format(DATETIME_FMT));
        return res;
    }

    @Override
    public String renderDynamicLabelTicket(Order order, OrderDetail detail, PrintTemplateDsl dsl, PrintTemplateOptions options) {
        if (dsl == null || detail == null) {
            return "";
        }
        if (("TEXT".equalsIgnoreCase(dsl.getMode()) || dsl.getBlocks() == null || dsl.getBlocks().isEmpty())
                && StringUtils.hasText(dsl.getRawTemplate())) {
            return renderRawLabelTemplate(order, detail, dsl, options);
        }
        StringBuilder sb = new StringBuilder();

        for (PrintTemplateDsl.TemplateBlock block : dsl.getBlocks()) {
            if (block == null || (block.getEnabled() != null && !block.getEnabled())) continue;
            String type = block.getType() != null ? block.getType().toUpperCase() : "";
            Map<String, Object> cfg = block.getConfig() != null ? block.getConfig() : Collections.emptyMap();

            switch (type) {
                case "HEADER":
                    String customTitle = cfg.get("customTitle") != null ? String.valueOf(cfg.get("customTitle")) : detail.getName();
                    String align = String.valueOf(cfg.getOrDefault("align", "CENTER"));
                    String size = String.valueOf(cfg.getOrDefault("size", "DOUBLE"));
                    boolean bold = !Boolean.FALSE.equals(cfg.get("bold"));
                    wrapStyledLine(sb, interpolateLabelVariables(customTitle, order, detail), align, size, bold);
                    break;
                case "CUSTOM_TEXT":
                    String customContent = cfg.get("content") != null ? String.valueOf(cfg.get("content")) : null;
                    if (StringUtils.hasText(customContent)) {
                        String text = interpolateLabelVariables(customContent, order, detail);
                        wrapStyledLine(sb, text, "LEFT", "NORMAL", false);
                    } else {
                        if (order != null && StringUtils.hasText(order.getTable_number())) {
                            sb.append("桌号: ").append(order.getTable_number()).append("<BR>");
                        }
                        if (StringUtils.hasText(detail.getSelectedSpicy())) {
                            sb.append("规格: ").append(formatPrintSpecInParens(detail.getSelectedSpicy())).append("<BR>");
                        }
                        sb.append("数量: ").append(detail.getQuantity() != null ? detail.getQuantity() : "1").append("<BR>");
                        sb.append("时间: ").append(LocalDateTime.now().format(DATETIME_FMT)).append("<BR>");
                    }
                    break;
                case "QRCODE":
                    renderDynamicQrCode(sb, cfg, options);
                    break;
                case "DIVIDER":
                    renderDynamicDivider(sb, cfg, dsl.getPaperSize());
                    break;
                case "FOOTER":
                    String thankText = cfg.get("thankText") != null ? String.valueOf(cfg.get("thankText")) : "";
                    if (StringUtils.hasText(thankText)) {
                        wrapStyledLine(sb, interpolateLabelVariables(thankText, order, detail), "CENTER", "NORMAL", false);
                    }
                    break;
                default:
                    break;
            }
        }
        sb.append("<BR>");
        if (Boolean.TRUE.equals(dsl.getAutoCut())) {
            sb.append("<CUT>");
        }
        return sb.toString();
    }

    private String interpolateLabelVariables(String text, Order order, OrderDetail detail) {
        if (!StringUtils.hasText(text)) return "";
        String res = text;
        if (detail != null) {
            String name = detail.getName() != null ? detail.getName() : "";
            res = res.replace("{goodsName}", name).replace("{品名}", name).replace("{商品名}", name).replace("{菜名}", name).replace("{name}", name);
            String spec = formatPrintSpecInParens(detail.getSelectedSpicy());
            res = res.replace("{spec}", spec).replace("{规格}", spec).replace("{口味}", spec).replace("{spicy}", spec);
            String qty = detail.getQuantity() != null ? String.valueOf(detail.getQuantity()) : "1";
            res = res.replace("{quantity}", qty).replace("{数量}", qty).replace("{份数}", qty).replace("{count}", qty);
            String price = detail.getTotal_price() != null ? String.format("%.2f", detail.getTotal_price()) : "0.00";
            res = res.replace("{price}", price).replace("{单价}", price).replace("{金额}", price);
        }
        if (order != null) {
            String tableNo = order.getTable_number() != null ? order.getTable_number() : "";
            res = res.replace("{tableNo}", tableNo).replace("{桌号}", tableNo).replace("{桌台号}", tableNo);
            String orderNo = order.getOrder_no() != null ? order.getOrder_no() : "";
            res = res.replace("{orderNo}", orderNo).replace("{订单号}", orderNo);
        }
        res = res.replace("{time}", LocalDateTime.now().format(DATETIME_FMT))
                 .replace("{时间}", LocalDateTime.now().format(DATETIME_FMT));
        return res;
    }

    @Override
    public String renderDynamicTestTicket(PrintTemplateDsl dsl, String testType, String deviceName, String transport, String brand, int shopId) {
        String type = StringUtils.hasText(testType) ? testType.trim().toLowerCase() : "order";
        StringBuilder sb = new StringBuilder();
        sb.append("<CB>打印测试单</CB><BR>");
        sb.append(buildDividerLine(dsl != null ? dsl.getPaperSize() : "58mm", null)).append("<BR>");
        sb.append("类型: ").append(type).append("<BR>");
        sb.append("门店: #").append(shopId).append("<BR>");
        sb.append("设备: ").append(deviceName != null ? deviceName : "默认设备")
                .append(" (").append(transport != null ? transport : "CLOUD").append(")<BR>");
        if (StringUtils.hasText(brand)) {
            sb.append("品牌: ").append(brand).append("<BR>");
        }
        sb.append("时间: ").append(LocalDateTime.now().format(DATETIME_FMT)).append("<BR>");
        sb.append(buildDividerLine(dsl != null ? dsl.getPaperSize() : "58mm", null)).append("<BR>");
        if ("refund".equals(type)) {
            sb.append("测试退款单<BR>");
            sb.append("原单号: TEST-000001<BR>");
            sb.append("退款金额: ¥0.01<BR>");
        } else if ("shift".equals(type)) {
            sb.append("测试交接班单<BR>");
            sb.append("班次: TEST-SHIFT<BR>");
        } else if ("kitchen".equals(type) || "kitchen_ticket".equals(type)) {
            sb.append("测试后厨单<BR>");
            sb.append("1x 测试菜品（免做得）<BR>");
        } else if ("cutter_test".equals(type)) {
            sb.append("切刀自检测试<BR>");
            sb.append("切刀动作正常<BR>");
        } else {
            sb.append("1x 测试商品   ¥10.00<BR>");
            sb.append("2x 测试商品B  ¥28.00<BR>");
            sb.append(buildDividerLine(dsl != null ? dsl.getPaperSize() : "58mm", null)).append("<BR>");
            sb.append("<B>合计: ¥38.00</B><BR>");
        }
        sb.append(buildDividerLine(dsl != null ? dsl.getPaperSize() : "58mm", null)).append("<BR>");
        sb.append("<C>**打印模块联调测试，非真实单据**</C><BR><BR>");
        if (dsl != null && Boolean.TRUE.equals(dsl.getAutoCut())) {
            sb.append("<CUT>");
        }
        return sb.toString();
    }

    // =========================================================================
    // DSL 转换与全场景默认预置模型生成
    // =========================================================================

    @Override
    public PrintTemplateDsl parseDsl(String templateJson) {
        if (!StringUtils.hasText(templateJson)) {
            return null;
        }
        try {
            return SPEC_MAPPER.readValue(templateJson, PrintTemplateDsl.class);
        } catch (Exception e) {
            log.warn("[printing] parseDsl failed: {}", e.getMessage());
            return null;
        }
    }

    @Override
    public PrintTemplateDsl buildDefaultDsl(String rawScenario, String paperSize) {
        String scenario = PrintScenario.normalizeScenario(rawScenario);
        PrintTemplateDsl dsl = new PrintTemplateDsl();
        dsl.setPaperSize(StringUtils.hasText(paperSize) ? paperSize : "58mm");
        dsl.setScenario(scenario);
        dsl.setAutoCut(true);
        dsl.setBeeper(true);
        dsl.setFeedLines(2);

        List<PrintTemplateDsl.TemplateBlock> blocks = new ArrayList<>();

        switch (scenario) {
            case "KITCHEN":
                // 厨房小票
                blocks.add(createBlock("block_header", "HEADER", "小票标题", mapOf("customTitle", "厨房小票", "titleType", "CUSTOM", "align", "CENTER", "size", "DOUBLE", "bold", true)));
                blocks.add(createBlock("block_order_info", "ORDER_INFO", "台号与单号", mapOf("showTableNo", true, "tableNoSize", "DOUBLE", "showDineInType", true, "showOrderNo", true, "showOrderTime", true)));
                blocks.add(createBlock("block_divider_1", "DIVIDER", "分割线", mapOf("text", buildDividerLine(paperSize, null))));
                blocks.add(createBlock("block_dish_items", "DISH_ITEMS", "后厨菜品明细", mapOf("showTableHead", true, "showUnitPrice", false, "showQuantity", true, "showTotalPrice", false, "specPosition", "INLINE", "spicyPrioritySort", true)));
                blocks.add(createBlock("block_remark", "REMARK", "整单备注", mapOf("size", "DOUBLE", "bold", true)));
                blocks.add(createBlock("block_divider_2", "DIVIDER", "底部分割线", mapOf("text", buildDividerLine(paperSize, null))));
                break;

            case "FULL_ORDER":
                // 前台整单（点菜单）
                blocks.add(createBlock("block_header", "HEADER", "店铺抬头", mapOf("titleType", "SHOP_NAME", "subTitle", "前台整单", "align", "CENTER", "size", "DOUBLE", "bold", true)));
                blocks.add(createBlock("block_order_info", "ORDER_INFO", "订单信息", mapOf("showTableNo", true, "tableNoSize", "DOUBLE", "showDineInType", true, "showOrderNo", true, "showOrderTime", true)));
                blocks.add(createBlock("block_divider_1", "DIVIDER", "分割线", mapOf("text", buildDividerLine(paperSize, null))));
                blocks.add(createBlock("block_dish_items", "DISH_ITEMS", "全单菜品明细", mapOf("showTableHead", true, "showUnitPrice", true, "showQuantity", true, "showTotalPrice", true, "specPosition", "INLINE")));
                blocks.add(createBlock("block_divider_2", "DIVIDER", "分割线", mapOf("text", buildDividerLine(paperSize, null))));
                blocks.add(createBlock("block_payment_summary", "PAYMENT_SUMMARY", "金额汇总", mapOf("showOriginalAmount", true, "showDiscountAmount", true, "showActualAmount", true, "actualAmountSize", "DOUBLE", "showPayChannel", false)));
                blocks.add(createBlock("block_remark", "REMARK", "整单备注", mapOf("size", "NORMAL", "bold", true)));
                blocks.add(createBlock("block_footer", "FOOTER", "底部提示", mapOf("thankText", "-----------请核对餐品-----------", "align", "CENTER", "showQrCode", false)));
                break;

            case "PRE_CHECKOUT":
                // 预结单
                blocks.add(createBlock("block_header", "HEADER", "店铺抬头", mapOf("titleType", "SHOP_NAME", "subTitle", "预结单(非结账凭据)", "align", "CENTER", "size", "DOUBLE", "bold", true)));
                blocks.add(createBlock("block_order_info", "ORDER_INFO", "订单信息", mapOf("showTableNo", true, "tableNoSize", "DOUBLE", "showDineInType", true, "showOrderNo", true, "showOrderTime", true)));
                blocks.add(createBlock("block_divider_1", "DIVIDER", "分割线", mapOf("text", buildDividerLine(paperSize, null))));
                blocks.add(createBlock("block_dish_items", "DISH_ITEMS", "消费明细", mapOf("showTableHead", true, "showUnitPrice", true, "showQuantity", true, "showTotalPrice", true, "specPosition", "INLINE")));
                blocks.add(createBlock("block_divider_2", "DIVIDER", "分割线", mapOf("text", buildDividerLine(paperSize, null))));
                blocks.add(createBlock("block_payment_summary", "PAYMENT_SUMMARY", "应结金额", mapOf("showOriginalAmount", true, "showDiscountAmount", true, "showActualAmount", true, "actualAmountSize", "DOUBLE", "showPayChannel", false)));
                blocks.add(createBlock("block_footer", "FOOTER", "核对提示", mapOf("thankText", "请核对消费明细，以最终结账为准", "align", "CENTER", "showQrCode", false)));
                break;

            case "CHECKOUT":
            case "ORDER":
            default:
                // 结账单
                blocks.add(createBlock("block_header", "HEADER", "店铺抬头", mapOf("titleType", "SHOP_NAME", "subTitle", "结账单", "align", "CENTER", "size", "DOUBLE", "bold", true)));
                blocks.add(createBlock("block_order_info", "ORDER_INFO", "订单信息", mapOf("showTableNo", true, "tableNoSize", "DOUBLE", "showDineInType", true, "showOrderNo", true, "showOrderTime", true, "showPayTime", true)));
                blocks.add(createBlock("block_divider_1", "DIVIDER", "分割线", mapOf("text", buildDividerLine(paperSize, null))));
                blocks.add(createBlock("block_dish_items", "DISH_ITEMS", "结算明细", mapOf("showTableHead", true, "showUnitPrice", true, "showQuantity", true, "showTotalPrice", true, "specPosition", "INLINE")));
                blocks.add(createBlock("block_divider_2", "DIVIDER", "分割线", mapOf("text", buildDividerLine(paperSize, null))));
                blocks.add(createBlock("block_payment_summary", "PAYMENT_SUMMARY", "实付汇总", mapOf("showOriginalAmount", true, "showDiscountAmount", true, "showActualAmount", true, "actualAmountSize", "DOUBLE", "showPayChannel", true)));
                blocks.add(createBlock("block_remark", "REMARK", "整单备注", mapOf("size", "NORMAL", "bold", false)));
                blocks.add(createBlock("block_footer", "FOOTER", "致谢与二维码", mapOf("thankText", "-----------感谢惠顾-----------", "align", "CENTER", "showQrCode", true, "qrCodeNote", "有任何问题可扫码反馈")));
                break;

            case "EXPEDITE":
                // 传菜单 / 催菜单
                blocks.add(createBlock("block_header", "HEADER", "单据抬头", mapOf("customTitle", "传菜单", "titleType", "CUSTOM", "align", "CENTER", "size", "DOUBLE", "bold", true)));
                blocks.add(createBlock("block_order_info", "ORDER_INFO", "桌号与单号", mapOf("showTableNo", true, "tableNoSize", "DOUBLE", "showOrderNo", true, "showOrderTime", true)));
                blocks.add(createBlock("block_divider_1", "DIVIDER", "分割线", mapOf("text", buildDividerLine(paperSize, null))));
                blocks.add(createBlock("block_dish_items", "DISH_ITEMS", "传菜明细", mapOf("showTableHead", false, "showUnitPrice", false, "showQuantity", true, "showTotalPrice", false, "specPosition", "INLINE")));
                blocks.add(createBlock("block_divider_2", "DIVIDER", "分割线", mapOf("text", buildDividerLine(paperSize, null))));
                blocks.add(createBlock("block_footer", "FOOTER", "凭证标注", mapOf("thankText", "传菜划单凭证", "align", "CENTER", "showQrCode", false)));
                break;

            case "TAKEOUT":
                // 外卖单
                blocks.add(createBlock("block_header", "HEADER", "店铺抬头", mapOf("titleType", "SHOP_NAME", "subTitle", "外卖配送单", "align", "CENTER", "size", "DOUBLE", "bold", true)));
                blocks.add(createBlock("block_order_info", "ORDER_INFO", "配送信息", mapOf("showDineInType", true, "showOrderNo", true, "showOrderTime", true)));
                blocks.add(createBlock("block_delivery_info", "DELIVERY_INFO", "收货人地址", mapOf("showReceiverName", true, "showReceiverPhone", true, "showDeliveryAddress", true, "showExpectedTime", true)));
                blocks.add(createBlock("block_divider_1", "DIVIDER", "分割线", mapOf("text", buildDividerLine(paperSize, null))));
                blocks.add(createBlock("block_dish_items", "DISH_ITEMS", "餐品明细", mapOf("showTableHead", true, "showUnitPrice", true, "showQuantity", true, "showTotalPrice", true, "specPosition", "INLINE")));
                blocks.add(createBlock("block_divider_2", "DIVIDER", "分割线", mapOf("text", buildDividerLine(paperSize, null))));
                blocks.add(createBlock("block_payment_summary", "PAYMENT_SUMMARY", "外卖结算", mapOf("showOriginalAmount", true, "showDiscountAmount", true, "showActualAmount", true, "actualAmountSize", "DOUBLE", "showPayChannel", true)));
                blocks.add(createBlock("block_remark", "REMARK", "买家备注", mapOf("size", "DOUBLE", "bold", true)));
                blocks.add(createBlock("block_footer", "FOOTER", "致谢", mapOf("thankText", "-----------祝您用餐愉快-----------", "align", "CENTER", "showQrCode", true)));
                break;

            case "PACKING":
                // 打包/到店自提独立核餐凭条（非支付凭证）
                blocks.add(createBlock("block_header", "HEADER", "打包单抬头", mapOf("customTitle", "打包单", "titleType", "CUSTOM", "align", "CENTER", "size", "DOUBLE", "bold", true)));
                blocks.add(createBlock("block_pickup_code", "CUSTOM_TEXT", "取餐码", mapOf("content", "取餐码：{取餐码}", "align", "CENTER", "size", "DOUBLE", "bold", true)));
                blocks.add(createBlock("block_order_info", "ORDER_INFO", "订单信息", mapOf("showDineInType", true, "showOrderNo", true, "showOrderTime", true)));
                blocks.add(createBlock("block_divider_1", "DIVIDER", "分割线", mapOf("text", buildDividerLine(paperSize, null))));
                blocks.add(createBlock("block_dish_items", "DISH_ITEMS", "打包餐品明细", mapOf("showTableHead", false, "showUnitPrice", false, "showQuantity", true, "showTotalPrice", false, "specPosition", "INLINE")));
                blocks.add(createBlock("block_remark", "REMARK", "打包备注", mapOf("size", "DOUBLE", "bold", true)));
                blocks.add(createBlock("block_divider_2", "DIVIDER", "底部分割线", mapOf("text", buildDividerLine(paperSize, null))));
                blocks.add(createBlock("block_footer", "FOOTER", "核餐提示", mapOf("thankText", "请核对餐品与数量后封装", "align", "CENTER", "showQrCode", false)));
                break;

            case "SHIFT":
                // 交接班报表
                blocks.add(createBlock("block_header", "HEADER", "报表抬头", mapOf("customTitle", "收银交接班报表", "titleType", "CUSTOM", "align", "CENTER", "size", "DOUBLE", "bold", true)));
                blocks.add(createBlock("block_divider_1", "DIVIDER", "分割线", mapOf("text", buildDividerLine(paperSize, null))));
                blocks.add(createBlock("block_custom_text", "CUSTOM_TEXT", "班次统计内容", mapOf()));
                blocks.add(createBlock("block_divider_2", "DIVIDER", "分割线", mapOf("text", buildDividerLine(paperSize, null))));
                blocks.add(createBlock("block_footer", "FOOTER", "签字确认", mapOf("thankText", "交接班核对无误请签字确认", "align", "CENTER", "showQrCode", false)));
                break;

            case "REFUND":
                // 退款单据
                blocks.add(createBlock("block_header", "HEADER", "退款单抬头", mapOf("customTitle", "退款单据", "titleType", "CUSTOM", "align", "CENTER", "size", "DOUBLE", "bold", true)));
                blocks.add(createBlock("block_divider_1", "DIVIDER", "分割线", mapOf("text", buildDividerLine(paperSize, null))));
                blocks.add(createBlock("block_order_info", "ORDER_INFO", "原订单与退款信息", mapOf("showOrderNo", true, "showTableNo", true)));
                blocks.add(createBlock("block_divider_2", "DIVIDER", "分割线", mapOf("text", buildDividerLine(paperSize, null))));
                blocks.add(createBlock("block_footer", "FOOTER", "提示语", mapOf("thankText", "**请妥善保管退款凭证**", "align", "CENTER", "showQrCode", false)));
                break;

            case "LABEL":
                // 商品标签
                blocks.add(createBlock("block_header", "HEADER", "标签品名", mapOf("customTitle", "商品标签", "titleType", "CUSTOM", "align", "CENTER", "size", "NORMAL", "bold", true)));
                break;

            case "TEST":
                // 自检测试单
                blocks.add(createBlock("block_header", "HEADER", "测试单抬头", mapOf("customTitle", "打印测试单", "titleType", "CUSTOM", "align", "CENTER", "size", "DOUBLE", "bold", true)));
                blocks.add(createBlock("block_divider_1", "DIVIDER", "分割线", mapOf("text", "================================")));
                blocks.add(createBlock("block_custom_text", "CUSTOM_TEXT", "测试详情", mapOf("content", "{customTestContent}")));
                blocks.add(createBlock("block_divider_2", "DIVIDER", "底部分割线", mapOf("text", buildDividerLine(paperSize, null))));
                blocks.add(createBlock("block_footer", "FOOTER", "测试说明", mapOf("thankText", "**打印模块联调测试，非真实单据**", "align", "CENTER", "showQrCode", false)));
                break;
        }

        dsl.setBlocks(blocks);
        return dsl;
    }

    private PrintTemplateDsl.TemplateBlock createBlock(String id, String type, String name, Map<String, Object> config) {
        PrintTemplateDsl.TemplateBlock b = new PrintTemplateDsl.TemplateBlock();
        b.setId(id);
        b.setType(type);
        b.setName(name);
        b.setEnabled(true);
        b.setConfig(config != null ? config : new LinkedHashMap<>());
        return b;
    }

    private Map<String, Object> mapOf(Object... kvs) {
        Map<String, Object> map = new LinkedHashMap<>();
        for (int i = 0; i < kvs.length - 1; i += 2) {
            map.put(String.valueOf(kvs[i]), kvs[i + 1]);
        }
        return map;
    }

    // =========================================================================
    // 纯文本模板与内部区块渲染辅助方法
    // =========================================================================

    private String renderRawTextTemplate(Order order, PrintTemplateDsl dsl, PrintTemplateOptions options) {
        String raw = dsl.getRawTemplate();
        if (!StringUtils.hasText(raw)) {
            return "";
        }
        // 按飞鹅云规则解析：<BR> 即换行符，归一为行分隔统一处理（if 条件块/变量插值/菜品迭代），
        // 避免原始数据中 <BR> 与换行混用导致重复换行；行处理后再统一还原为 <BR>
        raw = raw.replaceAll("(?i)<BR>", "\n");
        raw = parseConditionalBlocks(raw, name -> resolveOrderVar(name, order, options));

        List<OrderDetail> goodsList = order != null && order.getGoods_list() != null && !order.getGoods_list().isEmpty()
                ? order.getGoods_list()
                : Collections.emptyList();

        StringBuilder content = new StringBuilder();
        String[] lines = raw.split("\\r?\\n");

        for (String line : lines) {
            if (isDishIterationLine(line)) {
                for (OrderDetail good : goodsList) {
                    String renderedDishLine = renderDishIterationLine(line, good, dsl.getPaperSize());
                    content.append(renderedDishLine).append("<BR>");
                }
            } else {
                String processedLine = interpolateAllTextVariables(line, order, options);
                boolean unresolvedExplicitBinding = processedLine.matches(".*\\{[^}]{1,20}.*");
                if (unresolvedExplicitBinding && options != null) {
                    options.getBindingWarnings().add("字段绑定缺失，已隐藏所在行: " + line);
                }
                if (!hasMissingBinding(line, processedLine) && !unresolvedExplicitBinding) {
                    content.append(processedLine).append("<BR>");
                }
            }
        }

        return appendRawTemplateFooter(content, dsl, 2);
    }

    @Override
    public String renderCustomContent(String scenario, com.lanf.printing.model.PrintContext context, String content,
                                      PrintTemplateOptions options) {
        if (!StringUtils.hasText(content)) {
            return "";
        }
        String raw = content.replaceAll("(?i)<BR>", "\n");
        String norm = scenario != null ? scenario.toUpperCase() : "ORDER";
        Order order = context != null ? context.getOrder() : null;
        OrderDetail detail = context != null ? context.getOrderDetail() : null;
        Shift shift = context != null ? context.getShift() : null;
        Map<String, Object> extra = context != null && context.getExtra() != null ? context.getExtra() : Collections.emptyMap();

        switch (norm) {
            case "SHIFT":
                raw = parseConditionalBlocks(raw, name -> resolveShiftVar(name, shift, extra));
                break;
            case "REFUND":
                raw = parseConditionalBlocks(raw, name -> resolveRefundVar(name, order, extra));
                break;
            case "LABEL":
                raw = parseConditionalBlocks(raw, name -> resolveLabelVar(name, order, detail));
                break;
            default:
                raw = parseConditionalBlocks(raw, name -> resolveOrderVar(name, order, options));
        }

        StringBuilder result = new StringBuilder();
        for (String line : raw.split("\\r?\\n")) {
            if (!StringUtils.hasText(line)) {
                continue;
            }
            String processed;
            switch (norm) {
                case "SHIFT":
                    processed = interpolateShiftVariables(line, shift, extra);
                    break;
                case "REFUND":
                    processed = interpolateRefundVariables(line, order, extra);
                    break;
                case "LABEL":
                    processed = interpolateLabelVariables(line, order, detail);
                    break;
                default:
                    processed = interpolateAllTextVariables(line, order, options);
            }
            if (!hasMissingBinding(line, processed) && !processed.matches(".*\\{[^}]{1,20}.*")) {
                result.append(processed).append("<BR>");
            }
        }
        return result.toString();
    }

    /** 纯文本(rawTemplate)模板尾部：走纸/语音/切刀统一处理 */
    private String appendRawTemplateFooter(StringBuilder content, PrintTemplateDsl dsl, int defaultFeed) {
        int feedLines = dsl.getFeedLines() != null && dsl.getFeedLines() > 0 ? dsl.getFeedLines() : defaultFeed;
        for (int i = 0; i < feedLines; i++) {
            content.append("<BR>");
        }
        appendAudio(content, dsl);
        if (Boolean.TRUE.equals(dsl.getAutoCut()) && content.indexOf("<CUT>") < 0) {
            content.append("<CUT>");
        }
        return content.toString();
    }

    /** 交接班 rawTemplate：按 {shiftId}/{总单数}/{实收总额}/{printTime} 等变量逐行解析组装 */
    private String renderRawShiftTemplate(Shift shift, PrintTemplateDsl dsl, Map<String, Object> stats, PrintTemplateOptions options) {
        String raw = dsl.getRawTemplate();
        if (!StringUtils.hasText(raw)) {
            return "";
        }
        raw = raw.replaceAll("(?i)<BR>", "\n");
        raw = parseConditionalBlocks(raw, name -> resolveShiftVar(name, shift, stats));
        StringBuilder content = new StringBuilder();
        for (String line : raw.split("\\r?\\n")) {
            String processed = interpolateShiftVariables(line, shift, stats);
            if (!hasMissingBinding(line, processed) && !processed.matches(".*\\{[A-Za-z_][A-Za-z0-9_]*}.*")) {
                content.append(processed).append("<BR>");
            }
        }
        return appendRawTemplateFooter(content, dsl, 2);
    }

    /** 退款 rawTemplate：按 {orderNo}/{桌号}/{refundAmount}/{reason}/{operator} 等变量逐行解析组装 */
    private String renderRawRefundTemplate(Order order, PrintTemplateDsl dsl, Map<String, Object> refundInfo, PrintTemplateOptions options) {
        String raw = dsl.getRawTemplate();
        if (!StringUtils.hasText(raw)) {
            return "";
        }
        raw = raw.replaceAll("(?i)<BR>", "\n");
        raw = parseConditionalBlocks(raw, name -> resolveRefundVar(name, order, refundInfo));
        StringBuilder content = new StringBuilder();
        for (String line : raw.split("\\r?\\n")) {
            String processed = interpolateRefundVariables(line, order, refundInfo);
            if (!hasMissingBinding(line, processed) && !processed.matches(".*\\{[A-Za-z_][A-Za-z0-9_]*}.*")) {
                content.append(processed).append("<BR>");
            }
        }
        return appendRawTemplateFooter(content, dsl, 2);
    }

    /** 标签 rawTemplate：按 {goodsName}/{spec}/{quantity}/{price}/{tableNo}/{orderNo} 等变量逐行解析组装 */
    private String renderRawLabelTemplate(Order order, OrderDetail detail, PrintTemplateDsl dsl, PrintTemplateOptions options) {
        String raw = dsl.getRawTemplate();
        if (!StringUtils.hasText(raw)) {
            return "";
        }
        raw = raw.replaceAll("(?i)<BR>", "\n");
        raw = parseConditionalBlocks(raw, name -> resolveLabelVar(name, order, detail));
        StringBuilder content = new StringBuilder();
        for (String line : raw.split("\\r?\\n")) {
            String processed = interpolateLabelVariables(line, order, detail);
            if (!hasMissingBinding(line, processed) && !processed.matches(".*\\{[A-Za-z_][A-Za-z0-9_]*}.*")) {
                content.append(processed).append("<BR>");
            }
        }
        return appendRawTemplateFooter(content, dsl, 2);
    }

    private boolean isDishIterationLine(String line) {
        if (line == null) return false;
        return line.contains("{菜品}") || line.contains("{品名}") || line.contains("{商品}") || line.contains("{dishName}") || line.contains("{goodsName}");
    }

    private String renderDishIterationLine(String pattern, OrderDetail good, String paperSize) {
        String spec = formatPrintSpecInParens(good.getSelectedSpicy());
        String rawName = good.getName() != null ? good.getName() : "特色菜品";
        String shortName = stripSpecParens(rawName);
        String fullName = truncateToDisplayWidth(shortName, 8);
        int qty = parseQuantity(good.getQuantity());
        double price = calculatePrice(good);
        double totalPrice = calculateTotalPrice(good, price, qty);

        String res = pattern;
        res = res.replace("{规格}", spec).replace("{spec}", spec).replace("{口味}", spec).replace("{taste}", spec);

        if (res.contains("{菜品}") && res.contains("{单价}") && res.contains("{数量}") && res.contains("{金额}")) {
            return formatStandardDishColumns(fullName, price, qty, totalPrice, paperSize);
        }

        res = res.replace("{菜品}", fullName).replace("{品名}", fullName).replace("{商品}", fullName).replace("{dishName}", fullName).replace("{goodsName}", fullName);
        res = res.replace("{单价}", String.format("%.2f", price)).replace("{unitPrice}", String.format("%.2f", price)).replace("{price}", String.format("%.2f", price));
        res = res.replace("{数量}", String.valueOf(qty)).replace("{quantity}", String.valueOf(qty)).replace("{count}", String.valueOf(qty)).replace("{份数}", String.valueOf(qty));
        res = res.replace("{金额}", String.format("%.2f", totalPrice)).replace("{小计}", String.format("%.2f", totalPrice)).replace("{totalPrice}", String.format("%.2f", totalPrice)).replace("{amount}", String.format("%.2f", totalPrice));

        return res;
    }

    private String formatStandardDishColumns(String name, double price, int quantity, double totalPrice, String paperSize) {
        boolean is80mm = "80mm".equalsIgnoreCase(paperSize);
        int nameColWidth = is80mm ? 24 : 14;
        int priceColWidth = is80mm ? 8 : 6;
        int qtyColWidth = is80mm ? 6 : 4;
        int totalColWidth = is80mm ? 10 : 8;

        String truncatedName = truncateToDisplayWidth(name, nameColWidth);
        String paddedName = padEndDisplayWidth(truncatedName, nameColWidth);
        String formattedPrice = padStartDisplayWidth(String.format("%.2f", price), priceColWidth);
        String formattedQty = padStartDisplayWidth(String.valueOf(quantity), qtyColWidth);
        String formattedTotal = padStartDisplayWidth(String.format("%.2f", totalPrice), totalColWidth);

        return paddedName + formattedPrice + formattedQty + formattedTotal;
    }

    private int getDisplayWidth(String str) {
        if (str == null) return 0;
        int width = 0;
        for (char c : str.toCharArray()) {
            width += (c > 127) ? 2 : 1;
        }
        return width;
    }

    private String truncateToDisplayWidth(String str, int maxWidth) {
        if (str == null || maxWidth <= 0) return "";
        int currentWidth = 0;
        StringBuilder sb = new StringBuilder();
        for (char c : str.toCharArray()) {
            int charWidth = (c > 127) ? 2 : 1;
            if (currentWidth + charWidth > maxWidth) {
                break;
            }
            sb.append(c);
            currentWidth += charWidth;
        }
        return sb.toString();
    }

    private String padEndDisplayWidth(String str, int targetWidth) {
        if (str == null) str = "";
        int currentWidth = getDisplayWidth(str);
        StringBuilder sb = new StringBuilder(str);
        while (currentWidth < targetWidth) {
            sb.append(" ");
            currentWidth++;
        }
        return sb.toString();
    }

    private String padStartDisplayWidth(String str, int targetWidth) {
        if (str == null) str = "";
        int currentWidth = getDisplayWidth(str);
        StringBuilder sb = new StringBuilder();
        while (currentWidth < targetWidth) {
            sb.append(" ");
            currentWidth++;
        }
        sb.append(str);
        return sb.toString();
    }

    private String interpolateAllTextVariables(String line, Order order, PrintTemplateOptions options) {
        if (line == null) return "";
        String res = line;

        if (options != null && options.getBindings() != null) {
            for (Map.Entry<String, Object> entry : options.getBindings().entrySet()) {
                String token = "{" + entry.getKey() + "}";
                if (res.contains(token)) {
                    if (entry.getValue() == null || !StringUtils.hasText(String.valueOf(entry.getValue()))) {
                        options.getBindingWarnings().add("字段 " + entry.getKey() + " 无真实值，已隐藏所在行");
                        res = res.replace(token, "__PRINT_BINDING_MISSING__");
                    } else {
                        res = res.replace(token, String.valueOf(entry.getValue()));
                    }
                }
            }
        }

        if (res.contains("{二维码}") || res.contains("{qrCode}") || res.contains("{QR}")) {
            String qrUrl = options != null && StringUtils.hasText(options.getQrCodeUrl())
                    ? options.getQrCodeUrl()
                    : "";
            res = res.replace("{二维码}", "<QR>" + qrUrl + "</QR>")
                     .replace("{qrCode}", "<QR>" + qrUrl + "</QR>")
                     .replace("{QR}", "<QR>" + qrUrl + "</QR>");
        }

        String store = options != null && StringUtils.hasText(options.getBrandHeader()) ? options.getBrandHeader() : "";
        res = res.replace("{门店}", store)
                 .replace("{门店名称}", store)
                 .replace("{shopName}", store)
                 .replace("{brandHeader}", store)
                 .replace("{storeName}", store);

        String tableNo = order != null && StringUtils.hasText(order.getTable_number()) ? order.getTable_number() : "";
        res = res.replace("{桌号}", tableNo)
                 .replace("{桌台号}", tableNo)
                 .replace("{tableNo}", tableNo)
                 .replace("{table_number}", tableNo);

        String orderId = order != null && order.getId() != null ? String.valueOf(order.getId()) : "";
        res = res.replace("{订单ID}", orderId)
                 .replace("{订单Id}", orderId)
                 .replace("{订单id}", orderId)
                 .replace("{orderId}", orderId);

        String orderNo = order != null && StringUtils.hasText(order.getOrder_no()) ? order.getOrder_no() : "";
        String pickupCode = order != null && order.getId() != null ? String.valueOf(order.getId()) : "";
        res = res.replace("{取餐码}", pickupCode)
                 .replace("{取餐号}", pickupCode)
                 .replace("{pickupCode}", pickupCode);
        res = res.replace("{订单号}", orderNo)
                 .replace("{订单编号}", orderNo)
                 .replace("{流水号}", orderNo)
                 .replace("{orderNo}", orderNo);

        String dineIn = order != null ? resolvePrintModeLabel(order) : "";
        res = res.replace("{用餐方式}", dineIn)
                 .replace("{就餐方式}", dineIn)
                 .replace("{dineInType}", dineIn);

        boolean isAdd = (options != null && Boolean.TRUE.equals(options.getIsAddDish()))
                || (order != null && order.getOrderNumber() != null && order.getOrderNumber() > 1);
        String addDishTag = isAdd ? "【加菜】" : "";
        res = res.replace("{加菜}", addDishTag)
                 .replace("{加菜标识}", addDishTag)
                 .replace("{加菜单}", addDishTag)
                 .replace("{isAddDish}", addDishTag)
                 .replace("{addDish}", addDishTag);

        Object reprintBadgeObj = options != null && options.getBindings() != null ? options.getBindings().get("reprint_badge") : null;
        String reprintBadge = reprintBadgeObj != null ? String.valueOf(reprintBadgeObj) : "";
        res = res.replace("{补打}", reprintBadge)
                 .replace("{补打标识}", reprintBadge)
                 .replace("{reprint}", reprintBadge)
                 .replace("{reprintBadge}", reprintBadge);

        Object reprintOpObj = options != null && options.getBindings() != null ? options.getBindings().get("reprint_operator") : null;
        String reprintOp = reprintOpObj != null ? String.valueOf(reprintOpObj) : "";
        res = res.replace("{补打人}", reprintOp)
                 .replace("{reprintOperator}", reprintOp)
                 .replace("{reprint_operator}", reprintOp);

        Object reprintTimeObj = options != null && options.getBindings() != null ? options.getBindings().get("reprint_time") : null;
        String reprintTime = reprintTimeObj != null ? String.valueOf(reprintTimeObj) : "";
        res = res.replace("{补打时间}", reprintTime)
                 .replace("{reprintTime}", reprintTime)
                 .replace("{reprint_time}", reprintTime);

        SimpleDateFormat sdf = new SimpleDateFormat(TIME_FORMAT_DISPLAY);
        String orderTime = order != null && order.getOrder_time() != null ? sdf.format(order.getOrder_time()) : "";
        res = res.replace("{下单时间}", orderTime)
                 .replace("{orderTime}", orderTime)
                 .replace("{time}", orderTime)
                 .replace("{时间}", orderTime);

        String payTime = order != null && order.getPay_time() != null ? sdf.format(order.getPay_time()) : "";
        res = res.replace("{结账时间}", payTime)
                 .replace("{支付时间}", payTime)
                 .replace("{payTime}", payTime);

        String remark = order != null && StringUtils.hasText(order.getRemark()) ? order.getRemark().trim() : "";
        if (StringUtils.hasText(remark)) {
            res = res.replace("{备注}", remark)
                     .replace("{整单备注}", remark)
                     .replace("{顾客备注}", remark)
                     .replace("{remark}", remark);
        } else {
            // 备注为空：替换为缺失哨兵，raw 逐行渲染时整行隐藏（避免打印出"备注: "空行）
            res = res.replace("{备注}", "__PRINT_BINDING_MISSING__")
                     .replace("{整单备注}", "__PRINT_BINDING_MISSING__")
                     .replace("{顾客备注}", "__PRINT_BINDING_MISSING__")
                     .replace("{remark}", "__PRINT_BINDING_MISSING__");
        }

        double sett = order != null && order.getSett_amount() != null ? order.getSett_amount() : 0.0;
        double discount = order != null && order.getDiscount_amount() != null ? order.getDiscount_amount() : 0.0;
        // 原价合计与明细金额合计一致（demo 口径），明细缺失回退 sett+discount
        double goodsTotal = sumGoodsTotal(order);
        double original = goodsTotal > 0 ? goodsTotal : (sett + discount);

        res = res.replace("{原价}", String.format("%.2f", original))
                 .replace("{原价合计}", String.format("%.2f", original))
                 .replace("{商品原价}", String.format("%.2f", original))
                 .replace("{originalAmount}", String.format("%.2f", original));

        res = res.replace("{优惠}", String.format("%.2f", discount))
                 .replace("{优惠金额}", String.format("%.2f", discount))
                 .replace("{优惠减免}", String.format("%.2f", discount))
                 .replace("{discountAmount}", String.format("%.2f", discount));

        res = res.replace("{实付}", String.format("%.2f", sett))
                 .replace("{实付合计}", String.format("%.2f", sett))
                 .replace("{实付金额}", String.format("%.2f", sett))
                 .replace("{应收}", String.format("%.2f", sett))
                 .replace("{应收金额}", String.format("%.2f", sett))
                 .replace("{settAmount}", String.format("%.2f", sett))
                 .replace("{totalAmount}", String.format("%.2f", sett));

        String payMethod = order != null && StringUtils.hasText(order.getPayment_method()) ? order.getPayment_method() : "微信支付";
        res = res.replace("{支付方式}", payMethod)
                 .replace("{支付渠道}", payMethod)
                 .replace("{收款方式}", payMethod)
                 .replace("{payMethod}", payMethod)
                 .replace("{paymentMethod}", payMethod);

        String memberNo = "";
        if (order != null) {
            if (StringUtils.hasText(order.getMember_phone())) {
                memberNo = order.getMember_phone();
            } else if (StringUtils.hasText(order.getOpenid()) && order.getOpenid().length() >= 6) {
                memberNo = "VIP-" + order.getOpenid().substring(order.getOpenid().length() - 6);
            } else if (StringUtils.hasText(order.getPay_openid()) && order.getPay_openid().length() >= 6) {
                memberNo = "VIP-" + order.getPay_openid().substring(order.getPay_openid().length() - 6);
            }
        }
        res = res.replace("{会员卡号}", memberNo)
                 .replace("{会员号}", memberNo)
                 .replace("{会员手机号}", memberNo)
                 .replace("{memberPhone}", memberNo)
                 .replace("{vipCardNo}", memberNo);

        res = interpolateExtraFeeBindings(res, order);

        return res;
    }

    /** 整单附加费用/外卖信息 RAW 绑定：打包费(复用 OrderPackagingFeeCalculator)、配送费、收件人/电话/地址(查 t_takeout_delivery)；空值替换为哨兵整行隐藏 */
    private String interpolateExtraFeeBindings(String res, Order order) {
        if (order == null) {
            return res;
        }
        double goodsTotal = sumGoodsTotal(order);
        double packaging = OrderPackagingFeeCalculator.calcYuan(goodsTotal);
        if (packaging > 0) {
            String p = String.format("%.2f", packaging);
            res = res.replace("{打包费}", p).replace("{包装费}", p).replace("{餐盒费}", p).replace("{packagingFee}", p);
        } else {
            res = res.replace("{打包费}", "__PRINT_BINDING_MISSING__").replace("{包装费}", "__PRINT_BINDING_MISSING__")
                     .replace("{餐盒费}", "__PRINT_BINDING_MISSING__").replace("{packagingFee}", "__PRINT_BINDING_MISSING__");
        }
        Double deliveryFee = order.getDelivery_fee();
        if (deliveryFee == null && takeoutDeliveryService != null) {
            try {
                takeoutDeliveryService.enrichOrder(order);
            } catch (Exception ignored) {
            }
            deliveryFee = order.getDelivery_fee();
        }
        String d = (deliveryFee != null && deliveryFee > 0) ? String.format("%.2f", deliveryFee) : "";
        res = res.replace("{配送费}", d.isEmpty() ? "__PRINT_BINDING_MISSING__" : d)
                 .replace("{deliveryFee}", d.isEmpty() ? "__PRINT_BINDING_MISSING__" : d);
        if (res.contains("{收件人}") || res.contains("{receiverName}")
                || res.contains("{收件人电话}") || res.contains("{receiverPhone}")
                || res.contains("{配送地址}") || res.contains("{deliveryAddress}")) {
            TakeoutDelivery td = null;
            if (takeoutDeliveryService != null && order.getId() != null) {
                try {
                    td = takeoutDeliveryService.getByOrderId(order.getId());
                } catch (Exception ignored) {
                }
            }
            String name = td != null && StringUtils.hasText(td.getReceiver_name()) ? td.getReceiver_name() : "";
            String phone = td != null && StringUtils.hasText(td.getReceiver_phone()) ? td.getReceiver_phone() : "";
            String addr = td != null && StringUtils.hasText(td.getAddress_full()) ? td.getAddress_full() : "";
            res = res.replace("{收件人}", name.isEmpty() ? "__PRINT_BINDING_MISSING__" : name)
                     .replace("{receiverName}", name.isEmpty() ? "__PRINT_BINDING_MISSING__" : name)
                     .replace("{收件人电话}", phone.isEmpty() ? "__PRINT_BINDING_MISSING__" : phone)
                     .replace("{receiverPhone}", phone.isEmpty() ? "__PRINT_BINDING_MISSING__" : phone)
                     .replace("{配送地址}", addr.isEmpty() ? "__PRINT_BINDING_MISSING__" : addr)
                     .replace("{deliveryAddress}", addr.isEmpty() ? "__PRINT_BINDING_MISSING__" : addr);
        }
        return res;
    }

    private boolean hasMissingBinding(String original, String rendered) {
        return rendered != null && rendered.contains("__PRINT_BINDING_MISSING__");
    }

    private void appendAudio(StringBuilder content, PrintTemplateDsl dsl) {
        String audio = dsl == null ? null : dsl.getAudio();
        if (audio == null || "NONE".equalsIgnoreCase(audio)) return;
        String normalized = audio.trim().toUpperCase();
        if (Arrays.asList("COMMON", "MT", "ELE", "JD", "CANCEL", "REFUND").contains(normalized)) {
            content.append("<AUDIO-").append(normalized).append(">");
        }
    }

    private void renderBarcode(StringBuilder content, Map<String, Object> cfg, Order order, PrintTemplateOptions options) {
        String mode = cfg.get("mode") == null ? "BC128_B" : String.valueOf(cfg.get("mode")).toUpperCase();
        String value = cfg.get("value") == null ? "" : interpolateAllTextVariables(String.valueOf(cfg.get("value")), order, options);
        if (!StringUtils.hasText(value) || hasMissingBinding(String.valueOf(cfg.get("value")), value)) return;
        boolean valid = ("BC128_A".equals(mode) && value.matches("[\\x00-\\x5F]+"))
                || ("BC128_B".equals(mode) && value.matches("[\\x20-\\x7F]+"))
                || ("BC128_C".equals(mode) && value.matches("[0-9]+") && value.length() % 2 == 0);
        if (!valid) throw new IllegalArgumentException("条形码内容不符合 " + mode + " 规则");
        content.append("<").append(mode).append(">").append(value).append("</").append(mode).append("><BR>");
    }

    private int parsePositiveInt(Object obj, int defaultValue) {
        if (obj == null) return defaultValue;
        if (obj instanceof Number) return ((Number) obj).intValue();
        try {
            return Integer.parseInt(obj.toString().trim());
        } catch (Exception e) {
            return defaultValue;
        }
    }

    private Order copyOrderWithGoods(Order src, List<OrderDetail> goods) {
        Order copy = new Order();
        if (src != null) {
            copy.setId(src.getId());
            copy.setOrder_no(src.getOrder_no());
            copy.setShop_id(src.getShop_id());
            copy.setTable_number(src.getTable_number());
            copy.setDineInOrTakeOut(src.getDineInOrTakeOut());
            copy.setOrder_time(src.getOrder_time());
            copy.setPay_time(src.getPay_time());
            copy.setTransac_status(src.getTransac_status());
            copy.setSett_amount(src.getSett_amount());
            copy.setDiscount_amount(src.getDiscount_amount());
            copy.setService_fee(src.getService_fee());
            copy.setPayment_method(src.getPayment_method());
            copy.setRemark(src.getRemark());
            copy.setOpenid(src.getOpenid());
            copy.setPay_openid(src.getPay_openid());
        }
        copy.setGoods_list(goods);
        return copy;
    }

    private void renderDynamicHeader(StringBuilder content, Order order, Map<String, Object> cfg, PrintTemplateOptions options) {
        String titleType = String.valueOf(cfg.getOrDefault("titleType", "SHOP_NAME"));
        String title = "CUSTOM".equalsIgnoreCase(titleType) && cfg.get("customTitle") != null
                ? String.valueOf(cfg.get("customTitle"))
                : (options != null && StringUtils.hasText(options.getBrandHeader()) ? options.getBrandHeader() : "老肥油边王");
        title = interpolateVariables(title, order, options);
        String subTitle = cfg.get("subTitle") != null ? interpolateVariables(String.valueOf(cfg.get("subTitle")), order, options) : null;
        Object badge = options != null && options.getBindings() != null ? options.getBindings().get("reprint_badge") : null;
        if (badge != null && StringUtils.hasText(String.valueOf(badge))) {
            String badgeStr = String.valueOf(badge).trim();
            if (!title.contains(badgeStr) && !title.contains("补打")) {
                title = title + " " + badgeStr;
            }
        }
        String align = String.valueOf(cfg.getOrDefault("align", "CENTER"));
        String size = String.valueOf(cfg.getOrDefault("size", "DOUBLE"));
        boolean bold = Boolean.TRUE.equals(cfg.get("bold"));

        wrapStyledLine(content, title, align, size, bold);
        if (StringUtils.hasText(subTitle)) {
            wrapStyledLine(content, subTitle, align, "NORMAL", true);
        }
    }

    private void renderDynamicOrderInfo(StringBuilder content, Order order, Map<String, Object> cfg) {
        if (order == null) return;
        boolean showTableNo = !Boolean.FALSE.equals(cfg.get("showTableNo"));
        boolean showDineInType = !Boolean.FALSE.equals(cfg.get("showDineInType"));
        boolean showOrderNo = !Boolean.FALSE.equals(cfg.get("showOrderNo"));
        boolean showOrderTime = !Boolean.FALSE.equals(cfg.get("showOrderTime"));
        boolean showPayTime = Boolean.TRUE.equals(cfg.get("showPayTime"));

        String tableLabel = cfg.get("tableNoLabel") != null ? String.valueOf(cfg.get("tableNoLabel")) : "桌台号: ";
        String dineInLabel = cfg.get("dineInTypeLabel") != null ? String.valueOf(cfg.get("dineInTypeLabel")) : "用餐方式：";
        String orderNoLabel = cfg.get("orderNoLabel") != null ? String.valueOf(cfg.get("orderNoLabel")) : "订单编号：";
        String orderTimeLabel = cfg.get("timeLabel") != null ? String.valueOf(cfg.get("timeLabel")) : "下单时间：";
        String payTimeLabel = cfg.get("payTimeLabel") != null ? String.valueOf(cfg.get("payTimeLabel")) : "结账时间：";

        if (showTableNo && StringUtils.hasText(order.getTable_number())) {
            String size = String.valueOf(cfg.getOrDefault("tableNoSize", "DOUBLE"));
            String suffix = (tableLabel.contains("桌") || tableLabel.contains("台") || tableLabel.contains("号")) ? "" : "号桌";
            wrapStyledLine(content, tableLabel + order.getTable_number() + suffix, "LEFT", size, true);
        }
        if (showDineInType) {
            content.append(dineInLabel).append(resolvePrintModeLabel(order)).append("<BR>");
        }
        if (showOrderNo && StringUtils.hasText(order.getOrder_no())) {
            content.append(orderNoLabel).append(order.getOrder_no()).append("<BR>");
        }
        SimpleDateFormat sdf = new SimpleDateFormat(TIME_FORMAT_DISPLAY);
        if (showOrderTime && order.getOrder_time() != null) {
            content.append(orderTimeLabel).append(sdf.format(order.getOrder_time())).append("<BR>");
        }
        if (showPayTime && order.getPay_time() != null) {
            content.append(payTimeLabel).append(sdf.format(order.getPay_time())).append("<BR>");
        }
        if (cfg.get("customInfoText") != null && StringUtils.hasText(String.valueOf(cfg.get("customInfoText")))) {
            String customInfo = interpolateVariables(String.valueOf(cfg.get("customInfoText")), order);
            if (!hasMissingBinding(String.valueOf(cfg.get("customInfoText")), customInfo)) {
                content.append(customInfo).append("<BR>");
            }
        }
    }

    private void renderDynamicDishItems(StringBuilder content, List<OrderDetail> goodsList, Map<String, Object> cfg, String paperSize) {
        boolean showTableHead = !Boolean.FALSE.equals(cfg.get("showTableHead"));
        boolean showUnitPrice = !Boolean.FALSE.equals(cfg.get("showUnitPrice"));
        boolean showQuantity = !Boolean.FALSE.equals(cfg.get("showQuantity"));
        boolean showTotalPrice = !Boolean.FALSE.equals(cfg.get("showTotalPrice"));
        boolean spicyPrioritySort = Boolean.TRUE.equals(cfg.get("spicyPrioritySort"));

        String customHeader = cfg.get("headerText") != null ? String.valueOf(cfg.get("headerText")) : null;

        if (showTableHead) {
            if (StringUtils.hasText(customHeader)) {
                content.append(customHeader).append("<BR>");
            } else if (showUnitPrice && showTotalPrice) {
                content.append("名称　　　　　 单价  数量  金额<BR>");
            } else {
                content.append("名称　　　　　          数量<BR>");
            }
            if (Boolean.TRUE.equals(cfg.get("showHeadDivider"))) {
                String customDivider = cfg.get("dividerText") != null ? String.valueOf(cfg.get("dividerText")) : null;
                content.append(buildDividerLine(paperSize, customDivider)).append("<BR>");
            }
        }

        if (goodsList == null || goodsList.isEmpty()) {
            content.append("（暂无菜品明细）<BR>");
            return;
        }

        List<OrderDetail> sortedList = new ArrayList<>(goodsList);
        if (spicyPrioritySort) {
            sortedList.sort((a, b) -> Integer.compare(getSpicyPriority(b.getSelectedSpicy()), getSpicyPriority(a.getSelectedSpicy())));
        }

        for (OrderDetail good : sortedList) {
            String spec = formatPrintSpecInParens(good.getSelectedSpicy());
            String rawName = good.getName() != null ? good.getName() : "";
            String shortName = stripSpecParens(rawName);
            String fullName = truncateToDisplayWidth(shortName, 8);

            int quantity = parseQuantity(good.getQuantity());
            if (showUnitPrice && showTotalPrice) {
                double price = calculatePrice(good);
                double totalPrice = calculateTotalPrice(good, price, quantity);
                content.append(formatStandardDishColumns(fullName, price, quantity, totalPrice, paperSize)).append("<BR>");
            } else {
                if (fullName.length() > 8) {
                    fullName = fullName.substring(0, 8) + "..." + padEnd(4);
                }
                String formattedQuantity = padStart(String.valueOf(quantity), 2);
                content.append("<B>").append(fullName).append(formattedQuantity).append("</B><BR>");
            }
        }
    }

    private void renderDynamicPaymentSummary(StringBuilder content, Order order, Map<String, Object> cfg, String paperSize) {
        if (order == null) return;
        if (Boolean.TRUE.equals(cfg.get("showTopDivider"))) {
            String divider = cfg.get("dividerText") != null ? String.valueOf(cfg.get("dividerText")) : null;
            content.append(buildDividerLine(paperSize, divider)).append("<BR>");
        }

        boolean showOriginal = !Boolean.FALSE.equals(cfg.get("showOriginalAmount"));
        boolean showDiscount = !Boolean.FALSE.equals(cfg.get("showDiscountAmount"));
        boolean showActual = !Boolean.FALSE.equals(cfg.get("showActualAmount"));
        boolean showPayChannel = !Boolean.FALSE.equals(cfg.get("showPayChannel"));

        String originalLabel = cfg.get("originalLabel") != null ? String.valueOf(cfg.get("originalLabel")) : "原价合计：";
        String discountLabel = cfg.get("discountLabel") != null ? String.valueOf(cfg.get("discountLabel")) : "优惠减免：-";
        String actualLabel = cfg.get("actualLabel") != null ? String.valueOf(cfg.get("actualLabel")) : "实付合计：";
        String payChannelLabel = cfg.get("payChannelLabel") != null ? String.valueOf(cfg.get("payChannelLabel")) : "支付方式：";

        double sett = order.getSett_amount() != null ? order.getSett_amount() : 0.0;
        double discount = order.getDiscount_amount() != null ? order.getDiscount_amount() : 0.0;
        // 原价合计与 DISH_ITEMS 明细金额合计一致（飞鹅 demo 口径：合计=明细金额汇总）；明细缺失回退 sett+discount
        double goodsTotal = sumGoodsTotal(order);
        double original = goodsTotal > 0 ? goodsTotal : (sett + discount);
        // 打包费/配送费/服务费等附加费用：实付 = 明细合计 + 附加费 - 优惠，闭合票据内数字
        double extraFee = Math.round((sett + discount - goodsTotal) * 100.0) / 100.0;

        if (showOriginal && discount > 0) {
            content.append(originalLabel).append(String.format("%.2f", original)).append("元<BR>");
        }
        if (showDiscount && discount > 0) {
            content.append(discountLabel).append(String.format("%.2f", discount)).append("元<BR>");
        }
        if (!Boolean.FALSE.equals(cfg.get("showExtraFee")) && extraFee > 0.005) {
            content.append("附加费用(打包/配送/服务)：").append(String.format("%.2f", extraFee)).append("元<BR>");
        }
        if (showActual) {
            String actualSize = String.valueOf(cfg.getOrDefault("actualAmountSize", "DOUBLE"));
            boolean actualBold = !Boolean.FALSE.equals(cfg.get("actualAmountBold"));
            wrapStyledLine(content, actualLabel + String.format("%.2f", sett) + "元", "LEFT", actualSize, actualBold);
        }
        if (showPayChannel) {
            content.append(payChannelLabel).append(order.getPayment_method() != null ? order.getPayment_method() : "微信支付").append("<BR>");
        }
    }

    private void renderDynamicMemberInfo(StringBuilder content, Order order, Map<String, Object> cfg) {
        if (order == null || (!StringUtils.hasText(order.getOpenid()) && !StringUtils.hasText(order.getPay_openid()))) {
            return;
        }
        String label = cfg.get("label") != null ? String.valueOf(cfg.get("label")) : "会员卡号：VIP-";
        content.append(label).append(order.getOpenid() != null && order.getOpenid().length() >= 6 ? order.getOpenid().substring(0, 6) : "888888").append("<BR>");
        if (cfg.get("customNotice") != null && StringUtils.hasText(String.valueOf(cfg.get("customNotice")))) {
            content.append(String.valueOf(cfg.get("customNotice"))).append("<BR>");
        }
    }

    private void renderDynamicDeliveryInfo(StringBuilder content, Order order, Map<String, Object> cfg) {
        if (order == null || !"外卖".equals(order.getDineInOrTakeOut())) {
            return;
        }
        try {
            takeoutDeliveryService.enrichOrder(order);
        } catch (Exception ignored) {
        }
        TakeoutDelivery td = null;
        if (takeoutDeliveryService != null && order.getId() != null) {
            try {
                td = takeoutDeliveryService.getByOrderId(order.getId());
            } catch (Exception ignored) {
            }
        }
        if (td == null) {
            return;
        }
        if (!Boolean.FALSE.equals(cfg.get("showReceiverName")) && StringUtils.hasText(td.getReceiver_name())) {
            String label = cfg.get("receiverNameLabel") != null ? String.valueOf(cfg.get("receiverNameLabel")) : "收件人：";
            content.append(label).append(td.getReceiver_name()).append("<BR>");
        }
        if (!Boolean.FALSE.equals(cfg.get("showReceiverPhone")) && StringUtils.hasText(td.getReceiver_phone())) {
            String label = cfg.get("receiverPhoneLabel") != null ? String.valueOf(cfg.get("receiverPhoneLabel")) : "电话：";
            content.append(label).append(td.getReceiver_phone()).append("<BR>");
        }
        if (!Boolean.FALSE.equals(cfg.get("showDeliveryAddress")) && StringUtils.hasText(td.getAddress_full())) {
            String label = cfg.get("deliveryAddressLabel") != null ? String.valueOf(cfg.get("deliveryAddressLabel")) : "配送地址：";
            content.append(label).append(td.getAddress_full()).append("<BR>");
        }
        if (!Boolean.FALSE.equals(cfg.get("showDeliveryFee")) && order.getDelivery_fee() != null && order.getDelivery_fee() > 0) {
            String label = cfg.get("deliveryFeeLabel") != null ? String.valueOf(cfg.get("deliveryFeeLabel")) : "配送费：";
            content.append(label).append(String.format("%.2f", order.getDelivery_fee())).append("元<BR>");
        }
    }

    private void renderDynamicRemark(StringBuilder content, Order order, Map<String, Object> cfg) {
        if (order != null && StringUtils.hasText(order.getRemark())) {
            String label = cfg.get("label") != null ? String.valueOf(cfg.get("label")) : "备注：";
            String size = String.valueOf(cfg.getOrDefault("size", "DOUBLE"));
            boolean bold = !Boolean.FALSE.equals(cfg.get("bold"));
            wrapStyledLine(content, label + order.getRemark(), "LEFT", size, bold);
        }
    }

    private void renderDynamicCustomText(StringBuilder content, Order order, Map<String, Object> cfg) {
        String rawText = cfg.get("content") != null ? String.valueOf(cfg.get("content")) : "";
        if (StringUtils.hasText(rawText)) {
            String text = interpolateVariables(rawText, order);
            String align = String.valueOf(cfg.getOrDefault("align", "LEFT"));
            String size = String.valueOf(cfg.getOrDefault("size", "NORMAL"));
            boolean bold = Boolean.TRUE.equals(cfg.get("bold"));
            wrapStyledLine(content, text, align, size, bold);
        }
    }

    private String interpolateVariables(String text, Order order) {
        return interpolateVariables(text, order, null);
    }

    private String interpolateVariables(String text, Order order, PrintTemplateOptions options) {
        if (!StringUtils.hasText(text)) return text;
        return interpolateAllTextVariables(text, order, options);
    }

    /** 58mm 满行 32 半角字符 = 16 全角列；80mm 满行 48 半角字符 = 24 全角列 */
    private static final String DEFAULT_DIVIDER_TEXT = "--------------------------------";

    /** 按纸宽生成分割线：58mm=16 列(32 个 '-')，80mm=24 列(48 个 '-')；configured 为自定义文本时优先 */
    private String buildDividerLine(String paperSize, String configured) {
        if (configured != null && StringUtils.hasText(configured) && !DEFAULT_DIVIDER_TEXT.equals(configured)) {
            return configured;
        }
        int cols = "80mm".equals(paperSize) ? 48 : 32;
        StringBuilder line = new StringBuilder();
        for (int i = 0; i < cols; i++) {
            line.append('-');
        }
        return line.toString();
    }

    private void renderDynamicDivider(StringBuilder content, Map<String, Object> cfg, String paperSize) {
        String text = cfg.get("text") != null ? String.valueOf(cfg.get("text")) : null;
        if (StringUtils.hasText(text) && !DEFAULT_DIVIDER_TEXT.equals(text)) {
            content.append(text).append("<BR>");
            return;
        }
        // 未配置 text 或为默认 44 个 '-'：按纸宽生成满行虚线（58mm=16 列/32 个 '-', 80mm=24 列/48 个 '-'）
        String ch = cfg.get("char") != null ? String.valueOf(cfg.get("char")) : "-";
        int length = parsePositiveInt(cfg.get("length"), 0);
        if (length <= 0) {
            length = "80mm".equals(paperSize) ? 48 : 32;
        }
        if (length > 64) length = 64;
        StringBuilder line = new StringBuilder();
        for (int i = 0; i < length; i++) {
            line.append(ch);
        }
        content.append(line.toString()).append("<BR>");
    }

    private void renderDynamicQrCode(StringBuilder content, Map<String, Object> cfg, PrintTemplateOptions options) {
        String qrUrl = cfg.get("qrCodeUrl") != null ? String.valueOf(cfg.get("qrCodeUrl"))
                : (options != null ? options.getQrCodeUrl() : "https://u.wechat.com/EF9MZwaAbHhL79QCtBgAVAA?s=2");
        String qrNote = cfg.get("qrCodeNote") != null ? String.valueOf(cfg.get("qrCodeNote")) : null;
        if (StringUtils.hasText(qrUrl)) {
            content.append("<QR>").append(qrUrl).append("</QR><BR>");
            if (StringUtils.hasText(qrNote)) {
                content.append("<C>").append(qrNote).append("</C><BR>");
            }
        }
    }

    private void renderDynamicFooter(StringBuilder content, Map<String, Object> cfg, PrintTemplateOptions options) {
        String rawThank = cfg.get("thankText") != null ? String.valueOf(cfg.get("thankText")) : "感谢惠顾 欢迎再次光临";
        if (StringUtils.hasText(rawThank)) {
            wrapStyledLine(content, rawThank, "CENTER", "NORMAL", false);
        }
        if (cfg.get("noticeText") != null && StringUtils.hasText(String.valueOf(cfg.get("noticeText")))) {
            wrapStyledLine(content, String.valueOf(cfg.get("noticeText")), "CENTER", "NORMAL", false);
        }
        boolean showQr = !Boolean.FALSE.equals(cfg.get("showQrCode"));
        if (showQr) {
            renderDynamicQrCode(content, cfg, options);
        }
    }

    private void wrapStyledLine(StringBuilder sb, String text, String align, String size, boolean bold) {
        if (!StringUtils.hasText(text)) return;
        if (hasMissingBinding(text, text)) return;
        StringBuilder line = new StringBuilder();
        if ("DOUBLE".equalsIgnoreCase(size)) {
            line.append("<CB>").append(text).append("</CB>");
        } else if ("LARGE".equalsIgnoreCase(size)) {
            line.append("<B><L>").append(text).append("</L></B>");
        } else {
            if (bold) line.append("<B>");
            if ("CENTER".equalsIgnoreCase(align)) line.append("<C>");
            line.append(text);
            if ("CENTER".equalsIgnoreCase(align)) line.append("</C>");
            if (bold) line.append("</B>");
        }
        sb.append(line).append("<BR>");
    }

    private double calculatePrice(OrderDetail good) {
        if (good == null || good.getTotal_price() == null || good.getQuantity() == null) return 0d;
        try {
            double total = good.getTotal_price();
            int qty = parseQuantity(good.getQuantity());
            return qty > 0 ? total / qty : 0d;
        } catch (Exception ignored) {
            return 0d;
        }
    }

    private int parseQuantity(String raw) {
        if (raw == null) return 1;
        try {
            return Integer.parseInt(raw.trim());
        } catch (Exception e) {
            return 1;
        }
    }

    private double calculateTotalPrice(OrderDetail good, double unitPrice, int quantity) {
        if (good != null && good.getTotal_price() != null) {
            return good.getTotal_price().doubleValue();
        }
        return unitPrice * quantity;
    }

    private int getSpicyPriority(String specJson) {
        String text = getSpicyText(specJson);
        if (!StringUtils.hasText(text)) return 0;
        if (text.contains("特辣") || text.contains("爆辣")) return 3;
        if (text.contains("中辣")) return 2;
        if (text.contains("微辣")) return 1;
        return 0;
    }

    public static String getSpicyText(String spicy) {
        if (spicy == null || spicy.trim().isEmpty()) {
            return null;
        }
        String trimmed = spicy.trim();
        if ("null".equalsIgnoreCase(trimmed) || "{}".equals(trimmed) || "[]".equals(trimmed)) {
            return null;
        }
        if (trimmed.startsWith("(") && trimmed.endsWith(")")) {
            trimmed = trimmed.substring(1, trimmed.length() - 1).trim();
        }
        if (trimmed.isEmpty() || "null".equalsIgnoreCase(trimmed)) {
            return null;
        }

        try {
            JsonNode node = SPEC_MAPPER.readTree(trimmed);
            List<String> parts = new ArrayList<>();
            collectTextValues(node, parts);
            if (!parts.isEmpty()) {
                return String.join(",", parts);
            }
        } catch (Exception ignored) {
        }

        if (trimmed.contains(":") || trimmed.contains("：")) {
            int colon = trimmed.indexOf(':') >= 0 ? trimmed.indexOf(':') : trimmed.indexOf('：');
            String val = trimmed.substring(colon + 1).replace("\"", "").replace("}", "").replace("'", "").trim();
            if (isMeaningfulSpecPart(val)) {
                return val;
            }
        }

        String cleaned = trimmed.replace("\"", "").replace("{", "").replace("}", "").replace("'", "").trim();
        return isMeaningfulSpecPart(cleaned) ? cleaned : null;
    }

    private static void collectTextValues(JsonNode node, List<String> result) {
        if (node == null || node.isNull() || node.isMissingNode()) {
            return;
        }
        if (node.isTextual() || node.isNumber() || node.isBoolean()) {
            String s = node.asText().trim();
            if (isMeaningfulSpecPart(s)) {
                result.add(s);
            }
        } else if (node.isArray()) {
            for (JsonNode item : node) {
                collectTextValues(item, result);
            }
        } else if (node.isObject()) {
            if (node.hasNonNull("name")) {
                collectTextValues(node.get("name"), result);
            } else if (node.hasNonNull("value")) {
                collectTextValues(node.get("value"), result);
            } else {
                node.fields().forEachRemaining(entry -> collectTextValues(entry.getValue(), result));
            }
        }
    }

    private static boolean isMeaningfulSpecPart(String s) {
        return s != null && !s.trim().isEmpty() && !"null".equalsIgnoreCase(s.trim());
    }

    /** 去除菜名后的括号规格内容（如 "(微辣)" "(10串)"），仅保留菜名本体 */
    private static String stripSpecParens(String name) {
        if (name == null || name.isEmpty()) {
            return "";
        }
        return name.replaceAll("\\([^)]*\\)", "").trim();
    }
    public static String formatPrintSpecInParens(String specJson) {
        String text = getSpicyText(specJson);
        if (text == null || text.isEmpty()) {
            return "";
        }
        return "(" + text + ")";
    }

    private String padStart(String s, int len) {
        if (s == null) s = "";
        StringBuilder sb = new StringBuilder();
        for (int i = 0; i < len - s.length(); i++) {
            sb.append(" ");
        }
        sb.append(s);
        return sb.toString();
    }

    private String padEnd(int spaces) {
        StringBuilder sb = new StringBuilder();
        for (int i = 0; i < spaces; i++) {
            sb.append(" ");
        }
        return sb.toString();
    }

    private double sumGoodsTotal(Order order) {
        if (order == null || order.getGoods_list() == null) {
            return 0.0;
        }
        double sum = 0.0;
        for (OrderDetail d : order.getGoods_list()) {
            if (d != null && d.getTotal_price() != null) {
                sum += d.getTotal_price().doubleValue();
            }
        }
        return sum;
    }

    /** 是否外卖/外送单（用于退款单等场景的桌号回退判断） */
    private boolean isTakeoutOrder(Order order) {
        if (order == null || !StringUtils.hasText(order.getDineInOrTakeOut())) {
            return false;
        }
        String t = order.getDineInOrTakeOut().trim();
        return "外卖".equals(t) || "delivery".equalsIgnoreCase(t) || "waimai".equalsIgnoreCase(t) || "TakeOut".equalsIgnoreCase(t);
    }

    private String resolvePrintModeLabel(Order order) {
        if (order == null || !StringUtils.hasText(order.getDineInOrTakeOut())) {
            return "堂食";
        }
        return order.getDineInOrTakeOut().trim();
    }

    // =========================================================================
    // 条件块解析：{if:变量[=值]} ... {else} ... {/if}
    // 语法：{if:备注} 变量有值才保留；{if:用餐方式=堂食} 等于比较；{if:变量!=值} 不等于；支持嵌套与 else。
    // =========================================================================

    /** 解析 raw 模板中的条件块，按运行时条件剔除未命中分支，返回过滤后的文本（嵌套与 else 均支持） */
    private String parseConditionalBlocks(String raw, java.util.function.Function<String, String> valueResolver) {
        if (!StringUtils.hasText(raw)) {
            return "";
        }
        // 行内展开：{if:条件}A{else}B{/if} 同行写法拆成独立行（跨行写法不受影响）
        raw = raw.replaceAll("\\{if:\\{?[^}]*\\}?\\}", "\n$0\n")
                 .replace("{else}", "\n{else}\n")
                 .replace("{/if}", "\n{/if}\n");
        StringBuilder kept = new StringBuilder();
        boolean[] stack = new boolean[16];
        int depth = 0;
        for (String line : raw.split("\\r?\\n")) {
            String trimmed = line.trim();
            if (trimmed.isEmpty()) {
                continue;
            }
            if (trimmed.startsWith("{if:")) {
                int close = trimmed.indexOf('}', 4);
                if (close < 0) {
                    kept.append(line).append("\n");
                    continue;
                }
                String cond = trimmed.substring(4, close).trim();
                // 兼容 {if:{变量}} 带花括号的变量名写法：归一化为纯变量名
                if (cond.startsWith("{")) {
                    cond = cond.substring(1).trim();
                    if (cond.endsWith("}")) {
                        cond = cond.substring(0, cond.length() - 1).trim();
                    }
                }
                boolean parentActive = depth == 0 || stack[depth - 1];
                if (depth < stack.length) {
                    stack[depth] = parentActive && evalCondition(cond, valueResolver);
                    depth++;
                }
                continue;
            }
            if ("{else}".equals(trimmed)) {
                if (depth > 0) {
                    stack[depth - 1] = !stack[depth - 1];
                }
                continue;
            }
            if ("{/if}".equals(trimmed)) {
                if (depth > 0) {
                    depth--;
                }
                continue;
            }
            boolean visible = true;
            for (int i = 0; i < depth; i++) {
                if (!stack[i]) {
                    visible = false;
                    break;
                }
            }
            if (visible) {
                kept.append(line).append("\n");
            }
        }
        return kept.toString();
    }

    /** 条件求值：纯变量名=非空为真；变量=值/变量==值=相等为真；变量!=值=不等为真 */
    private boolean evalCondition(String cond, java.util.function.Function<String, String> valueResolver) {
        if (!StringUtils.hasText(cond)) {
            return false;
        }
        String c = cond.trim();
        String op = null;
        String varName;
        String expected = null;
        if (c.contains("!=")) {
            op = "!=";
        } else if (c.contains("==")) {
            op = "==";
        } else if (c.contains("=")) {
            op = "=";
        }
        if (op != null) {
            int idx = c.indexOf(op);
            varName = c.substring(0, idx).trim();
            expected = c.substring(idx + op.length()).trim();
        } else {
            varName = c;
        }
        String value = valueResolver.apply(varName);
        if (op == null) {
            return value != null && StringUtils.hasText(value);
        }
        boolean eq = value != null && value.trim().equals(expected);
        return "!=".equals(op) ? !eq : eq;
    }

    /** 订单场景变量值解析（供 {if:} 条件求值；空值口径与插值一致） */
    private String resolveOrderVar(String name, Order order, PrintTemplateOptions options) {
        if (name == null) {
            return "";
        }
        String n = name.trim();
        String tableNo = order != null && StringUtils.hasText(order.getTable_number()) ? order.getTable_number().trim() : "";
        String orderNo = order != null && StringUtils.hasText(order.getOrder_no()) ? order.getOrder_no().trim() : "";
        switch (n) {
            case "用餐方式": case "就餐方式": case "dineInType": case "dine_in":
                return order != null && StringUtils.hasText(order.getDineInOrTakeOut()) ? order.getDineInOrTakeOut().trim() : "堂食";
            case "桌号": case "桌台号": case "tableNo": case "table_number":
                return tableNo;
            case "取餐码": case "取餐号": case "pickupCode":
                return order != null && order.getId() != null ? String.valueOf(order.getId()) : "";
            case "订单号": case "订单编号": case "orderNo":
                return orderNo;
            case "备注": case "顾客备注": case "remark":
                return order != null && StringUtils.hasText(order.getRemark()) ? order.getRemark().trim() : "";
            case "加菜": case "加菜单": case "加菜标识": case "isAddDish":
                boolean isAdd = (options != null && Boolean.TRUE.equals(options.getIsAddDish()))
                        || (order != null && order.getOrderNumber() != null && order.getOrderNumber() > 1);
                return isAdd ? "true" : "";
            default:
                return "";
        }
    }

    /** 交接班场景变量值解析（供 {if:} 条件求值） */
    private String resolveShiftVar(String name, Shift shift, Map<String, Object> stats) {
        if (name == null) {
            return "";
        }
        String n = name.trim();
        if ("总单数".equals(n) || "orderCount".equals(n) || "单数".equals(n)) {
            return shift != null && shift.getOrder_count() != null ? String.valueOf(shift.getOrder_count()) : "";
        }
        if ("实收总额".equals(n) || "totalAmount".equals(n) || "营业额".equals(n)) {
            return shift != null && shift.getTotal_amount() != null ? String.valueOf(shift.getTotal_amount()) : "";
        }
        if (stats != null && stats.containsKey(n)) {
            return stats.get(n) != null ? String.valueOf(stats.get(n)) : "";
        }
        return "";
    }

    /** 退款场景变量值解析（供 {if:} 条件求值） */
    private String resolveRefundVar(String name, Order order, Map<String, Object> refundInfo) {
        if (name == null) {
            return "";
        }
        String n = name.trim();
        if (refundInfo != null && refundInfo.containsKey(n)) {
            return refundInfo.get(n) != null ? String.valueOf(refundInfo.get(n)) : "";
        }
        if ("桌号".equals(n) || "桌台号".equals(n) || "tableNo".equals(n)) {
            return order != null && StringUtils.hasText(order.getTable_number()) ? order.getTable_number().trim() : "";
        }
        if ("原订单号".equals(n) || "订单号".equals(n) || "orderNo".equals(n)) {
            return order != null && StringUtils.hasText(order.getOrder_no()) ? order.getOrder_no().trim() : "";
        }
        return "";
    }

    /** 标签场景变量值解析（供 {if:} 条件求值） */
    private String resolveLabelVar(String name, Order order, OrderDetail detail) {
        if (name == null) {
            return "";
        }
        String n = name.trim();
        if (detail != null) {
            if ("品名".equals(n) || "商品名".equals(n) || "菜名".equals(n) || "goodsName".equals(n)) {
                return detail.getName() != null ? detail.getName() : "";
            }
            if ("数量".equals(n) || "quantity".equals(n) || "份数".equals(n)) {
                return detail.getQuantity() != null ? String.valueOf(detail.getQuantity()) : "";
            }
        }
        if (order != null) {
            if ("桌号".equals(n) || "tableNo".equals(n)) {
                return order.getTable_number() != null ? order.getTable_number().trim() : "";
            }
            if ("订单号".equals(n) || "orderNo".equals(n)) {
                return order.getOrder_no() != null ? order.getOrder_no().trim() : "";
            }
        }
        return "";
    }
}
