package com.lanf.integration.web;

import com.lanf.config.ZsqSystemSettings;
import com.lanf.integration.service.ZsqAuthService;
import com.lanf.integration.web.dto.ApiResult;
import com.lanf.integration.web.dto.LoginApiRequest;
import com.lanf.integration.web.dto.LoginApiResponse;
import javax.validation.Valid;
import org.springframework.http.HttpHeaders;
import org.springframework.web.bind.annotation.*;

import java.util.Map;

/**
 * 你方服务器：登录 / 会话校验。
 * <p>后续请求在 Header 携带：Authorization: Bearer xxx（与真省钱一致）</p>
 */
@RestController
@RequestMapping("/api/zsq/auth")
public class ZsqAuthController {

    private final ZsqAuthService authService;
    private final ZsqSystemSettings zsqSystemSettings;

    public ZsqAuthController(ZsqAuthService authService, ZsqSystemSettings zsqSystemSettings) {
        this.authService = authService;
        this.zsqSystemSettings = zsqSystemSettings;
    }

    /**
     * 商户/接口方登录，返回真省钱 Authorization token。
     */
    @PostMapping("/login")
    public ApiResult<LoginApiResponse> login(@Valid @RequestBody LoginApiRequest request) {
        ZsqAuthService.LoginResult result = authService.login(
                request.getUsername(),
                request.getPassword(),
                request.getRole(),
                request.getLoginMode(),
                request.getSmsCode());
        return ApiResult.ok(new LoginApiResponse(result.getAuthorization(), result.getRole()));
    }

    /**
     * 使用 yml 配置的账号登录（后台任务用）。
     */
    @PostMapping("/login/config")
    public ApiResult<LoginApiResponse> loginByConfig() {
        throw new org.springframework.web.server.ResponseStatusException(
                org.springframework.http.HttpStatus.GONE, "配置账号代理接口已停用，请使用管理端配送接口");
    }

    /**
     * 校验 token 是否有效。
     */
    @GetMapping("/verify")
    public ApiResult<Map<String, Object>> verify(
            @RequestHeader(HttpHeaders.AUTHORIZATION) String authorization) {
        return ApiResult.ok(authService.verifySession(authorization));
    }
}
