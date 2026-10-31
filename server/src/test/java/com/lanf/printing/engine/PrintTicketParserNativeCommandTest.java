package com.lanf.printing.engine;

import com.lanf.printing.model.PrintPreviewResult.PrintPreviewElement;
import org.junit.jupiter.api.Test;

import java.util.List;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertTrue;

class PrintTicketParserNativeCommandTest {

    @Test
    void preservesFeieNativeCommandsInPreviewAst() {
        String raw = "<LOGO><BR><CB>标题</CB><BR><L><W><BOLD>高宽粗体</BOLD></W></L><BR>"
                + "<RIGHT>右侧</RIGHT><BR><QR>https://example.test/order/1</QR><BR>"
                + "<BC128_A>ABC123</BC128_A><BR><PLUGIN><BR><AUDIO-COMMON><BR><CUT>";

        List<PrintPreviewElement> elements = PrintTicketParser.parseElements(raw);

        assertTrue(elements.stream().anyMatch(e -> "LOGO".equals(e.getType())));
        assertTrue(elements.stream().anyMatch(e -> "QRCODE".equals(e.getType())));
        assertTrue(elements.stream().anyMatch(e -> "BARCODE".equals(e.getType())
                && "BC128_A".equals(e.getMeta().get("mode"))));
        assertTrue(elements.stream().anyMatch(e -> "CASH_DRAWER".equals(e.getType())));
        assertTrue(elements.stream().anyMatch(e -> "AUDIO".equals(e.getType())));
        assertTrue(elements.stream().anyMatch(e -> "CUT".equals(e.getType())));
        PrintPreviewElement styled = elements.stream().filter(e -> "高宽粗体".equals(e.getText())).findFirst()
                .orElseThrow(() -> new AssertionError("missing styled text element"));
        assertEquals(2, styled.getMeta().get("heightScale"));
        assertEquals(2, styled.getMeta().get("widthScale"));
        assertTrue(styled.isBold());
    }
}
