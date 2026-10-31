package com.lanf.payment.channel.wechat;

import org.w3c.dom.Document;
import org.w3c.dom.Element;
import org.w3c.dom.Node;
import org.w3c.dom.NodeList;
import org.xml.sax.InputSource;

import javax.crypto.Mac;
import javax.crypto.spec.SecretKeySpec;
import javax.xml.XMLConstants;
import javax.xml.parsers.DocumentBuilderFactory;
import java.io.StringReader;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.util.Map;
import java.util.TreeMap;

/** 微信支付 V2 XML 编解码、HMAC-SHA256 签名与验签。 */
public final class WechatPayV2Codec {
    private WechatPayV2Codec() {}

    public static String sign(Map<String, String> values, String apiV2Key) {
        if (apiV2Key == null || apiV2Key.length() != 32) {
            throw new IllegalArgumentException("微信 APIv2 密钥必须为 32 位");
        }
        StringBuilder canonical = new StringBuilder();
        for (Map.Entry<String, String> entry : new TreeMap<>(values).entrySet()) {
            if ("sign".equals(entry.getKey()) || entry.getValue() == null || entry.getValue().isEmpty()) continue;
            if (canonical.length() > 0) canonical.append('&');
            canonical.append(entry.getKey()).append('=').append(entry.getValue());
        }
        canonical.append("&key=").append(apiV2Key);
        try {
            Mac mac = Mac.getInstance("HmacSHA256");
            mac.init(new SecretKeySpec(apiV2Key.getBytes(StandardCharsets.UTF_8), "HmacSHA256"));
            return hex(mac.doFinal(canonical.toString().getBytes(StandardCharsets.UTF_8)));
        } catch (Exception e) {
            throw new IllegalStateException("微信 V2 签名失败", e);
        }
    }

    public static boolean verify(Map<String, String> values, String apiV2Key) {
        String actual = values.get("sign");
        if (actual == null || actual.isEmpty()) return false;
        byte[] expected = sign(values, apiV2Key).getBytes(StandardCharsets.US_ASCII);
        return MessageDigest.isEqual(expected, actual.toUpperCase().getBytes(StandardCharsets.US_ASCII));
    }

    public static String toXml(Map<String, String> values) {
        StringBuilder xml = new StringBuilder("<xml>");
        for (Map.Entry<String, String> entry : values.entrySet()) {
            if (entry.getValue() == null) continue;
            xml.append('<').append(entry.getKey()).append('>')
                    .append(escape(entry.getValue()))
                    .append("</").append(entry.getKey()).append('>');
        }
        return xml.append("</xml>").toString();
    }

    public static Map<String, String> parse(String xml) {
        if (xml == null || xml.trim().isEmpty()) throw new IllegalArgumentException("微信 V2 响应为空");
        if (xml.toUpperCase().contains("<!DOCTYPE") || xml.toUpperCase().contains("<!ENTITY")) {
            throw new IllegalArgumentException("微信 V2 XML 包含禁止的声明");
        }
        try {
            DocumentBuilderFactory factory = DocumentBuilderFactory.newInstance();
            factory.setFeature(XMLConstants.FEATURE_SECURE_PROCESSING, true);
            factory.setFeature("http://apache.org/xml/features/disallow-doctype-decl", true);
            factory.setFeature("http://xml.org/sax/features/external-general-entities", false);
            factory.setFeature("http://xml.org/sax/features/external-parameter-entities", false);
            factory.setXIncludeAware(false);
            factory.setExpandEntityReferences(false);
            factory.setAttribute(XMLConstants.ACCESS_EXTERNAL_DTD, "");
            factory.setAttribute(XMLConstants.ACCESS_EXTERNAL_SCHEMA, "");
            Document document = factory.newDocumentBuilder().parse(new InputSource(new StringReader(xml)));
            Element root = document.getDocumentElement();
            if (root == null || !"xml".equals(root.getTagName())) throw new IllegalArgumentException("微信 V2 XML 根节点非法");
            Map<String, String> result = new TreeMap<>();
            NodeList children = root.getChildNodes();
            for (int i = 0; i < children.getLength(); i++) {
                Node node = children.item(i);
                if (node.getNodeType() == Node.ELEMENT_NODE) result.put(node.getNodeName(), node.getTextContent());
            }
            return result;
        } catch (IllegalArgumentException e) {
            throw e;
        } catch (Exception e) {
            throw new IllegalArgumentException("微信 V2 XML 解析失败", e);
        }
    }

    private static String escape(String value) {
        return value.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")
                .replace("\"", "&quot;").replace("'", "&apos;");
    }

    private static String hex(byte[] bytes) {
        char[] digits = "0123456789ABCDEF".toCharArray();
        char[] out = new char[bytes.length * 2];
        for (int i = 0; i < bytes.length; i++) {
            int v = bytes[i] & 0xff;
            out[i * 2] = digits[v >>> 4]; out[i * 2 + 1] = digits[v & 0x0f];
        }
        return new String(out);
    }
}
