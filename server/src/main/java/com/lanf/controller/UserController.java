package com.lanf.controller;
import com.lanf.dto.R;
import com.lanf.service.IUserService;
import lombok.RequiredArgsConstructor;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/user")
@RequiredArgsConstructor
public class UserController {
    private final IUserService userService;



    // 用户注册
    @PostMapping("/register")
    public R<Void> register(
            @RequestParam String openid,
            @RequestParam String phone,
            @RequestParam(required = false) String invite_code
    ) {
        return R.fail("ssss");
    }
}