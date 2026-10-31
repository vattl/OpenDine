package com.lanf.payment.channel.wechat;

import org.junit.jupiter.api.Test;

import java.util.LinkedHashMap;
import java.util.Map;

import static org.junit.jupiter.api.Assertions.*;

class WechatPayV2CodecTest {
    private static final String KEY = "0123456789abcdef0123456789abcdef";

    @Test
    void signsSortedNonEmptyFieldsWithHmacSha256() {
        Map<String, String> values = new LinkedHashMap<>();
        values.put("mch_id", "1900000109");
        values.put("appid", "wx2421b1c4370ec43b");
        values.put("empty", "");
        values.put("sign", "ignored");

        String sign = WechatPayV2Codec.sign(values, KEY);

        assertEquals(64, sign.length());
        assertEquals(sign.toUpperCase(), sign);
        values.put("sign", sign);
        assertTrue(WechatPayV2Codec.verify(values, KEY));
        values.put("mch_id", "tampered");
        assertFalse(WechatPayV2Codec.verify(values, KEY));
    }

    @Test
    void roundTripsEscapedXmlAndRejectsDoctype() {
        Map<String, String> values = new LinkedHashMap<>();
        values.put("body", "A&B <订单>");
        values.put("nonce_str", "nonce");
        String xml = WechatPayV2Codec.toXml(values);
        assertEquals("A&B <订单>", WechatPayV2Codec.parse(xml).get("body"));

        assertThrows(IllegalArgumentException.class, () -> WechatPayV2Codec.parse(
                "<!DOCTYPE xml [<!ENTITY xxe SYSTEM \"file:///etc/passwd\">]><xml><body>&xxe;</body></xml>"));
    }
}
