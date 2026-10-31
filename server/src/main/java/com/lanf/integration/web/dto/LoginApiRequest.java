package com.lanf.integration.web.dto;

import javax.validation.constraints.NotBlank;

public class LoginApiRequest {

    @NotBlank
    private String username;

    @NotBlank
    private String password;

    /** merchant | partner，默认 merchant */
    private String role = "merchant";

    private String loginMode = "password";

    private String smsCode = "";

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

    public String getRole() {
        return role;
    }

    public void setRole(String role) {
        this.role = role;
    }

    public String getLoginMode() {
        return loginMode;
    }

    public void setLoginMode(String loginMode) {
        this.loginMode = loginMode;
    }

    public String getSmsCode() {
        return smsCode;
    }

    public void setSmsCode(String smsCode) {
        this.smsCode = smsCode;
    }
}
