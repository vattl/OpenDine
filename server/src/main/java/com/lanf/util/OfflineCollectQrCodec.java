package com.lanf.util;

import com.google.zxing.BarcodeFormat;
import com.google.zxing.BinaryBitmap;
import com.google.zxing.DecodeHintType;
import com.google.zxing.EncodeHintType;
import com.google.zxing.MultiFormatReader;
import com.google.zxing.NotFoundException;
import com.google.zxing.Result;
import com.google.zxing.client.j2se.BufferedImageLuminanceSource;
import com.google.zxing.client.j2se.MatrixToImageWriter;
import com.google.zxing.common.BitMatrix;
import com.google.zxing.common.HybridBinarizer;
import com.google.zxing.qrcode.QRCodeWriter;
import com.google.zxing.qrcode.decoder.ErrorCorrectionLevel;
import org.springframework.util.StringUtils;

import javax.imageio.ImageIO;
import java.awt.image.BufferedImage;
import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.util.Collections;
import java.util.EnumMap;
import java.util.HashMap;
import java.util.Map;

/**
 * 线下收款码：从上传图片解码二维码内容、按收款串生成二维码 PNG（供对方 App 扫一扫）。
 */
public final class OfflineCollectQrCodec {

    private OfflineCollectQrCodec() {
    }

    public static String decodeFirstQrPayload(InputStream imageStream) throws IOException, NotFoundException {
        BufferedImage image = ImageIO.read(imageStream);
        if (image == null) {
            throw new IOException("无法识别为图片");
        }
        BufferedImageLuminanceSource source = new BufferedImageLuminanceSource(image);
        BinaryBitmap bitmap = new BinaryBitmap(new HybridBinarizer(source));
        Map<DecodeHintType, Object> hints = new EnumMap<>(DecodeHintType.class);
        hints.put(DecodeHintType.POSSIBLE_FORMATS, Collections.singletonList(BarcodeFormat.QR_CODE));
        Result result = new MultiFormatReader().decode(bitmap, hints);
        return result.getText();
    }

    public static boolean looksLikeWechatCollectPayload(String text) {
        if (!StringUtils.hasText(text)) {
            return false;
        }
        String t = text.trim();
        return t.startsWith("wxp://")
                || t.startsWith("https://wx.tenpay.com/")
                || t.startsWith("http://wx.tenpay.com/")
                || t.contains("wx.tenpay.com");
    }

    public static boolean looksLikeAlipayCollectPayload(String text) {
        if (!StringUtils.hasText(text)) {
            return false;
        }
        String t = text.trim();
        return t.startsWith("https://qr.alipay.com/")
                || t.startsWith("http://qr.alipay.com/")
                || t.startsWith("alipays://")
                || t.contains("qr.alipay.com");
    }

    public static byte[] encodeQrPng(String content, int size) throws Exception {
        if (!StringUtils.hasText(content)) {
            throw new IllegalArgumentException("二维码内容不能为空");
        }
        Map<EncodeHintType, Object> hints = new HashMap<>();
        hints.put(EncodeHintType.ERROR_CORRECTION, ErrorCorrectionLevel.M);
        hints.put(EncodeHintType.MARGIN, 1);
        QRCodeWriter writer = new QRCodeWriter();
        BitMatrix matrix = writer.encode(content, BarcodeFormat.QR_CODE, size, size, hints);
        BufferedImage img = MatrixToImageWriter.toBufferedImage(matrix);
        ByteArrayOutputStream out = new ByteArrayOutputStream();
        ImageIO.write(img, "PNG", out);
        return out.toByteArray();
    }
}
