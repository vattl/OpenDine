package com.lanf.printing.engine;

import com.lanf.printing.model.PrintPreviewResult.PrintPreviewElement;
import org.springframework.util.StringUtils;

import java.util.ArrayList;
import java.util.Arrays;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

/**
 * 打印指令标签解析器：将带飞鹅/ESC-POS标签的原生打印文本解析为纯文本与结构化 AST 元素树
 */
public class PrintTicketParser {

    private static final Pattern TAG_PATTERN = Pattern.compile("<[^>]+>");
    private static final Pattern QR_PATTERN = Pattern.compile("<(?:QR|qrcode)>(.*?)</(?:QR|qrcode)>", Pattern.CASE_INSENSITIVE);
    private static final Pattern BARCODE_PATTERN = Pattern.compile("<(BC128_A|BC128_B|BC128_C|BC|BC128_Auto|barcode)>(.*?)</\\1>", Pattern.CASE_INSENSITIVE);
    private static final Pattern AUDIO_PATTERN = Pattern.compile("<(AUDIO-(?:COMMON|MT|ELE|JD|CANCEL|REFUND))>", Pattern.CASE_INSENSITIVE);

    /**
     * 将原生小票内容转换为纯文本
     */
    public static String toPlainText(String rawContent) {
        if (!StringUtils.hasText(rawContent)) {
            return "";
        }
        String text = rawContent.replace("<BR>", "\n")
                .replace("<br>", "\n")
                .replace("<CUT>", "\n\n")
                .replace("<cut>", "\n\n");
        return TAG_PATTERN.matcher(text).replaceAll("");
    }

    public static List<PrintPreviewElement> parseElements(String rawContent) {
        List<PrintPreviewElement> elements = new ArrayList<>();
        if (!StringUtils.hasText(rawContent)) {
            return elements;
        }

        // 按行拆分（兼容 <BR> 与真实换行符）
        String normalized = rawContent.replace("\r\n", "<BR>").replace("\n", "<BR>")
                // Native controls may be adjacent in a valid printer payload. Delimit them for the AST only.
                .replaceAll("(?i)<(LOGO|PLUGIN|CUT|AUDIO-(?:COMMON|MT|ELE|JD|CANCEL|REFUND))>", "<BR><$1><BR>");
        String[] lines = normalized.split("(?i)<BR>");

        for (String rawLine : lines) {
            String trimmed = rawLine.trim();

            // 1. 设备原生指令。这些不是可见文本，仍需作为 AST 节点返回，
            // 否则预览会错误地宣称设备将执行一个不存在的动作。
            if (trimmed.equalsIgnoreCase("<LOGO>")) {
                PrintPreviewElement el = new PrintPreviewElement("LOGO", null);
                el.setAlign("CENTER");
                elements.add(el);
                continue;
            }
            if (trimmed.equalsIgnoreCase("<PLUGIN>")) {
                elements.add(new PrintPreviewElement("CASH_DRAWER", null));
                continue;
            }
            Matcher audioMatcher = AUDIO_PATTERN.matcher(trimmed);
            if (audioMatcher.matches()) {
                PrintPreviewElement el = new PrintPreviewElement("AUDIO", audioMatcher.group(1).toUpperCase());
                elements.add(el);
                continue;
            }

            // 2. 二维码标签检测
            Matcher qrMatcher = QR_PATTERN.matcher(trimmed);
            if (qrMatcher.find()) {
                PrintPreviewElement el = new PrintPreviewElement("QRCODE", qrMatcher.group(1));
                el.setAlign("CENTER");
                elements.add(el);
                continue;
            }

            // 3. 条形码标签检测
            Matcher bcMatcher = BARCODE_PATTERN.matcher(trimmed);
            if (bcMatcher.find()) {
                PrintPreviewElement el = new PrintPreviewElement("BARCODE", bcMatcher.group(2));
                el.setAlign("CENTER");
                Map<String, Object> meta = new HashMap<>();
                meta.put("mode", bcMatcher.group(1).toUpperCase());
                el.setMeta(meta);
                elements.add(el);
                continue;
            }

            // 4. 切刀指令
            if (trimmed.equalsIgnoreCase("<CUT>")) {
                elements.add(PrintPreviewElement.cut());
                continue;
            }

            // 5. 解析行样式（按飞鹅官方规则：<B>=放大一倍，<BOLD>=加粗，<DB>/<R> 非官方标签按普通文本）
            boolean bold = false;
            String size = "NORMAL";
            String align = "LEFT";

            // 对齐优先级：CB（居中放大）> C（居中）> RIGHT（右对齐）
            if (hasTag(rawLine, "CB")) {
                size = "DOUBLE";
                align = "CENTER";
            } else if (hasTag(rawLine, "C")) {
                align = "CENTER";
            } else if (hasTag(rawLine, "RIGHT")) {
                align = "RIGHT";
            }

            // <B> = 放大一倍（DOUBLE），不是加粗；<BOLD> = 唯一加粗来源
            if (hasTag(rawLine, "B")) {
                size = "DOUBLE";
            }
            if (hasTag(rawLine, "BOLD")) {
                bold = true;
            }

            int heightScale = hasTag(rawLine, "L") ? 2 : 1;
            int widthScale = hasTag(rawLine, "W") ? 2 : 1;
            if (hasTag(rawLine, "CB")) {
                heightScale = 2;
                widthScale = 2;
            }

            // 提取纯文本内容，但保留空格与缩进（保证真实排版一模一样）
            String cleanText = TAG_PATTERN.matcher(rawLine).replaceAll("");
            if (cleanText.endsWith("\r")) {
                cleanText = cleanText.substring(0, cleanText.length() - 1);
            }

            // 空行保留（保证换行间距 100% 一致）
            if (cleanText.isEmpty()) {
                elements.add(styledText("", align, false, "NORMAL", heightScale, widthScale));
                continue;
            }

            // 5. 分割线判定
            String testDivider = cleanText.trim();
            if (testDivider.length() >= 4 && testDivider.matches("[-=*#_─~]+")) {
                elements.add(PrintPreviewElement.divider(cleanText));
                continue;
            }

            // 6. 大标题判定 (带 CB/B 标签或大号双倍字体)
            if ("DOUBLE".equals(size) || "LARGE".equals(size)) {
                elements.add(PrintPreviewElement.header(cleanText, align, bold, size));
                continue;
            }

            // 7. 默认普通文本行 (保留原样空格对齐、列间距)
            elements.add(styledText(cleanText, align, bold, size, heightScale, widthScale));
        }

        return elements;
    }

    private static PrintPreviewElement styledText(String text, String align, boolean bold, String size,
                                                   int heightScale, int widthScale) {
        PrintPreviewElement element = PrintPreviewElement.text(text, align, bold, size);
        if (heightScale != 1 || widthScale != 1) {
            Map<String, Object> meta = new HashMap<>();
            meta.put("heightScale", heightScale);
            meta.put("widthScale", widthScale);
            element.setMeta(meta);
        }
        return element;
    }
    /**
     * 精确匹配飞鹅标签（大小写不敏感），避免 <B> 误伤 <BR>/<BOLD>/<BC128_B>/<CB>，<C> 误伤 <CB>/<CUT>/<BC128_C>。
     */
    private static boolean hasTag(String line, String tagName) {
        return Pattern.compile("(?i)<" + Pattern.quote(tagName) + ">").matcher(line).find();
    }
}