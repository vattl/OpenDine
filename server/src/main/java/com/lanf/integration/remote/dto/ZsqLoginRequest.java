package com.lanf.integration.remote.dto;

import com.fasterxml.jackson.annotation.JsonIgnoreProperties;

/** 对应真省钱 POST /store/staff/login 或 /pt/app/login */
@JsonIgnoreProperties(ignoreUnknown = true)
public class ZsqLoginRequest {

    private String username;
    private String password;
    private int type;
    private int loginType;
    private String code = "";

    public String getUsername() {
        return username;
    }

    public void setUsername(String username) {
        this.username = username;
    }

    public String getPassword() {
        return password;
    }

    public void setPassword(String password) {
        this.password = password;
    }

    public int getType() {
        return type;
    }

    public void setType(int type) {
        this.type = type;
    }

    public int getLoginType() {
        return loginType;
    }

    public void setLoginType(int loginType) {
        this.loginType = loginType;
    }

    public String getCode() {
        return code;
    }

    public void setCode(String code) {
        this.code = code;
    }
}
