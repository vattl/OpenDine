package com.lanf.test;

import com.alibaba.fastjson.JSON;
import com.alibaba.fastjson.JSONObject;
import com.lanf.properties.WeixinProperties;
import com.lanf.util.HttpClientUtil;

public class AccessTokenUrl {

    public static void main(String[] args) {
        WeixinProperties weixinProperties=new WeixinProperties();
        HttpClientUtil httpClientUtil = HttpClientUtil.getInstance();
        String url="https://api.weixin.qq.com/cgi-bin/token" + "?grant_type=client_credential&appid=" + "wxf83815a208478de9" + "&secret=" + "4d7677ac1966d88e10afe1e22043f267";
        System.out.println(url);
        String token = httpClientUtil.sendHttpGet(url);
        System.out.println(token);
        JSONObject jsonObject = JSON.parseObject(token);
        System.out.println(jsonObject.get("access_token"));

    }
}
