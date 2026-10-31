package com.lanf.integration.remote.dto;

import com.fasterxml.jackson.annotation.JsonIgnoreProperties;

@JsonIgnoreProperties(ignoreUnknown = true)
public class ZsqLoginTokenData {

    private String token;
    private String tokenHead;

    public String getToken() {
        return token;
    }

    public void setToken(String token) {
        this.token = token;
    }

    public String getTokenHead() {
        return tokenHead;
    }

    public void setTokenHead(String tokenHead) {
        this.tokenHead = tokenHead;
    }

    public String fullAuthorization() {
        return (tokenHead == null ? "" : tokenHead) + (token == null ? "" : token);
    }
}
