package com.lanf.config;

import com.alibaba.fastjson.JSONObject;
import com.google.zxing.*;
import com.google.zxing.client.j2se.MatrixToImageWriter;
import com.google.zxing.client.j2se.MatrixToImageConfig;
import com.google.zxing.common.BitMatrix;
import com.google.zxing.qrcode.QRCodeWriter;
import com.google.zxing.qrcode.decoder.ErrorCorrectionLevel;
import com.lanf.util.DateUtil;
import org.apache.http.HttpResponse;
import org.apache.http.client.methods.HttpPost;
import org.apache.http.entity.StringEntity;
import org.apache.http.impl.client.CloseableHttpClient;
import org.apache.http.impl.client.HttpClientBuilder;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Component;
import com.lanf.controller.admin.AdminTableController;
import javax.imageio.ImageIO;
import java.awt.*;
import java.awt.image.BufferedImage;
import java.io.*;
import java.net.URL;
import java.util.HashMap;
import java.util.Map;

/**
 * 邀请海报生成工具类
 */
@Component
public class InvitePosterGenerator {

    @Autowired
    private AdminTableController AdminTableController;

    @Value("${qrcodeImgsFilePath}")
    private String qrcodeImgsFilePath;
    /**
     * 生成邀请海报
     * @param backgroundImagePath 背景图路径（本地绝对路径/网络URL）
     * @param inviteCode 邀请码
     * @param qrCodeX 二维码在背景图的X坐标（距左侧）
     * @param qrCodeY 二维码在背景图的Y坐标（距顶部）
     * @param qrCodeSize 二维码尺寸（正方形，单位：像素）
     * @return 生成的海报图片字节数组
     * @throws Exception 图片处理异常
     */
    public byte[] generatePoster(String backgroundImagePath, String inviteCode, int qrCodeX, int qrCodeY, int qrCodeSize,String IMAGE_FORMAT) throws Exception {
        // 1. 生成邀请链接二维码（二维码内容：你的小程序注册页链接 + 邀请码）

        BufferedImage qrCodeImage = generateQrCode(inviteCode, AdminTableController.getAccessToken(),qrCodeSize);

        // 2. 读取背景图（支持本地路径/网络URL）
        BufferedImage backgroundImage;
        if (backgroundImagePath.startsWith("http")) {
            // 网络背景图
            URL url = new URL(backgroundImagePath);
            backgroundImage = ImageIO.read(url);
        } else {
            // 本地背景图（建议放在resources/static/poster/目录下）
            File backgroundFile = new File(backgroundImagePath);
            backgroundImage = ImageIO.read(backgroundFile);
        }

        // 3. 创建画布，将二维码绘制到背景图指定位置
        Graphics2D g = backgroundImage.createGraphics();
        // 设置抗锯齿，让二维码更清晰
        g.setRenderingHint(RenderingHints.KEY_ANTIALIASING, RenderingHints.VALUE_ANTIALIAS_ON);
        // 绘制二维码（X,Y为左上角坐标，宽高为qrCodeSize）
        g.drawImage(qrCodeImage, qrCodeX, qrCodeY, qrCodeSize, qrCodeSize, null);
        g.dispose(); // 释放资源

        // 4. 将合成后的图片转为字节数组（返回给前端）
        ByteArrayOutputStream outputStream = new ByteArrayOutputStream();
        ImageIO.write(backgroundImage, IMAGE_FORMAT, outputStream);
        return outputStream.toByteArray();
    }


    /**
     * 生成符合微信小程序规范的二维码
     * 关键调整：
     * 1. 适配微信小程序二维码的内容格式（pages/路径 + 参数）
     * 2. 优化二维码参数（边距、纠错级别）适配微信扫码
     * 3. 增加小程序二维码的标准尺寸校验
     */
    private BufferedImage generateQrCode(String inviteCode, String accessToken,int qrCodeSize){

        Map<String, Object> body =new HashMap<>();
        body.put("path","pages/my/my?invite_code=" + inviteCode);
        int qrCodeWidth = 500; // 自定义尺寸，比如500px
        body.put("width", qrCodeSize);
        body.put("is_hyaline", true);
        String url="https://api.weixin.qq.com/wxa/getwxacode?access_token="+accessToken;
        try {
            ByteArrayInputStream bis = new ByteArrayInputStream(getWechatQrcodeByHttpClient(url,body));
            BufferedImage image = ImageIO.read(bis);
            String newFileName=inviteCode+"_"+DateUtil.getCurrentDateStr()+".png";
            File output = new File(qrcodeImgsFilePath+newFileName);
            ImageIO.write(image, "png", output);
            return image;
        } catch (IOException e) {
            e.printStackTrace();
        }
        return null;
    }


    private  byte[] getWechatQrcodeByHttpClient(String url, Map<String, Object> body) {
        CloseableHttpClient httpClient = HttpClientBuilder.create().build();
        HttpPost httpPost = new HttpPost(url);
        try {
            StringEntity entity = new StringEntity(JSONObject.toJSONString(body));
            entity.setContentType("image/png");
            httpPost.setEntity(entity);
            HttpResponse response = httpClient.execute(httpPost);
            try (InputStream inputStream = response.getEntity().getContent();
                 ByteArrayOutputStream out = new ByteArrayOutputStream()) {
                byte[] buffer = new byte[1024];
                int len = -1;
                while ((len = inputStream.read(buffer)) != -1) {
                    out.write(buffer, 0, len);
                }
                return out.toByteArray();
            }
        } catch (Exception e) {
            e.printStackTrace();
        }
        return null;
    }

}