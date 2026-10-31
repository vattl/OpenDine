package com.lanf.service.impl;

import com.fasterxml.jackson.core.JsonProcessingException;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.lanf.entity.User;
import com.lanf.service.IUserService;
import com.lanf.service.WechatMiniProgramAuthService;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Service;
import org.springframework.util.StringUtils;
import org.springframework.web.client.RestClientException;
import org.springframework.web.client.RestTemplate;

import java.util.Date;
import java.util.Map;

@Service
public class WechatMiniProgramAuthServiceImpl implements WechatMiniProgramAuthService {

    private static final Logger log = LoggerFactory.getLogger(WechatMiniProgramAuthServiceImpl.class);

    private final RestTemplate restTemplate;
    private final ObjectMapper objectMapper;
    private final IUserService userService;

    @Value("${weixin.appid}")
    private String appid;

    @Value("${weixin.secret}")
    private String appsecret;

    public WechatMiniProgramAuthServiceImpl(RestTemplate restTemplate,
                                            ObjectMapper objectMapper,
                                            IUserService userService) {
        this.restTemplate = restTemplate;
        this.objectMapper = objectMapper;
        this.userService = userService;
    }

    @Override
    public String exchangeCodeForOpenid(String code) {
        if (!StringUtils.hasText(code)) {
            throw new IllegalArgumentException("code不能为空");
        }
        String url = "https://api.weixin.qq.com/sns/jscode2session"
                + "?appid=" + appid
                + "&secret=" + appsecret
                + "&js_code=" + code.trim()
                + "&grant_type=authorization_code";
        try {
            String responseStr = restTemplate.getForObject(url, String.class);
            if (responseStr == null || responseStr.trim().isEmpty()) {
                throw new IllegalStateException("微信接口返回空内容");
            }
            @SuppressWarnings("unchecked")
            Map<String, Object> response = objectMapper.readValue(responseStr, Map.class);
            if (response.containsKey("errcode")) {
                int errCode = 0;
                Object errCodeObj = response.get("errcode");
                if (errCodeObj instanceof Number) {
                    errCode = ((Number) errCodeObj).intValue();
                }
                String errMsg = (String) response.getOrDefault("errmsg", "未知错误");
                throw new IllegalStateException("获取openid失败[" + errCode + "]: " + errMsg);
            }
            String openid = (String) response.get("openid");
            String sessionKey = (String) response.get("session_key");
            if (!StringUtils.hasText(openid)) {
                throw new IllegalStateException("未返回有效的openid");
            }
            if (!StringUtils.hasText(sessionKey)) {
                throw new IllegalStateException("未返回有效的sessionKey");
            }
            upsertUser(openid.trim(), sessionKey.trim());
            return openid.trim();
        } catch (RestClientException e) {
            log.error("调用微信 jscode2session 失败", e);
            throw new IllegalStateException("网络请求失败: " + e.getMessage());
        } catch (JsonProcessingException e) {
            log.error("解析微信 jscode2session 响应失败", e);
            throw new IllegalStateException("数据解析错误");
        }
    }

    @Override
    public String resolveOpenid(String openid, String wxCode) {
        if (StringUtils.hasText(wxCode)) {
            return exchangeCodeForOpenid(wxCode);
        }
        if (StringUtils.hasText(openid)) {
            return openid.trim();
        }
        return null;
    }

    private void upsertUser(String openid, String sessionKey) {
        User user = userService.getUserByOpenid(openid);
        if (user == null) {
            user = new User();
            user.setOpenid(openid);
            user.setTime(new Date());
            user.setUser_type(0);
            user.setSession_key(sessionKey);
            userService.save(user);
            return;
        }
        user.setSession_key(sessionKey);
        Date registerTime = user.getTime() != null ? user.getTime() : new Date();
        if (user.getTime() == null) {
            user.setTime(registerTime);
        }
        user.setUser_type(isRegisteredOver7Days(registerTime) ? 1 : 0);
        userService.updateById(user);
    }

    private static boolean isRegisteredOver7Days(Date registerTime) {
        if (registerTime == null) {
            return false;
        }
        long sevenDaysMillis = 7L * 24 * 60 * 60 * 1000;
        return (System.currentTimeMillis() - registerTime.getTime()) > sevenDaysMillis;
    }
}
