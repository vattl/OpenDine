package com.lanf.payment.notify;

import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Service;

import javax.servlet.http.HttpServletRequest;
import javax.servlet.http.HttpServletResponse;
import java.io.IOException;

@Service
public class WechatPaymentNotifyService {

    @Autowired
    private WechatPaymentNotifyHandler wechatPaymentNotifyHandler;

    public void handle(HttpServletRequest request, HttpServletResponse response) throws IOException {
        wechatPaymentNotifyHandler.handle(request, response);
    }
}
