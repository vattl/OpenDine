package com.lanf.test;

import com.alibaba.fastjson.JSON;
import com.alibaba.fastjson.JSONObject;
import com.lanf.properties.WeixinProperties;
import com.lanf.util.HttpClientUtil;

import org.apache.http.Header;
import org.apache.http.HttpEntity;
import org.apache.http.HttpResponse;
import org.apache.http.NameValuePair;
import org.apache.http.client.entity.UrlEncodedFormEntity;
import org.apache.http.client.methods.CloseableHttpResponse;
import org.apache.http.client.methods.HttpPost;
import org.apache.http.entity.BasicHttpEntity;
import org.apache.http.entity.EntityTemplate;
import org.apache.http.entity.StringEntity;
import org.apache.http.impl.client.CloseableHttpClient;
import org.apache.http.impl.client.HttpClientBuilder;
import org.apache.http.impl.client.HttpClients;

import org.apache.http.message.BasicNameValuePair;
import org.springframework.util.LinkedMultiValueMap;
import org.springframework.util.MultiValueMap;

import javax.imageio.ImageIO;
import java.awt.image.BufferedImage;
import java.io.*;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

public class QrCodeTest {

    public static void main(String[] args)throws Exception {
        Map<String, Object> body =new HashMap<>();
        body.put("path","pages/index/index");
        String url="https://api.weixin.qq.com/wxa/getwxacode?access_token="+"75_eM1Pi1kUeaxXZ82wFJdp0L0eWcD4uS7Z6HDvViU4ycxvggAQZv5pG8NhzF7Z_7fbXp0W2ig9ZM5tkzApghBqyZ2Ku-_UPbWGoxB4BwQcfw6jcU9FzMRkMN8YfToSQRbAAAHFG";
        System.out.println();

        try {
            ByteArrayInputStream bis = new ByteArrayInputStream(getWechatQrcodeByHttpClient(url,body));
            BufferedImage image = ImageIO.read(bis);
            File output = new File("D:\\output.png");
            ImageIO.write(image, "png", output);
            System.out.println("Image file created successfully.");
        } catch (IOException e) {
            e.printStackTrace();
        }

    }

    public static byte[] getWechatQrcodeByHttpClient(String url, Map<String, Object> body) {
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
