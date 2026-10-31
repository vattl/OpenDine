package com.lanf.integration.web.dto;

public class LoginApiResponse {

    private String authorization;
    private String role;

    public LoginApiResponse(String authorization, String role) {
        this.authorization = authorization;
        this.role = role;
    }

    public String getAuthorization() {
        return authorization;
    }

    public void setAuthorization(String authorization) {
        this.authorization = authorization;
    }

    public String getRole() {
        return role;
    }

    public void setRole(String role) {
        this.role = role;
    }
}
