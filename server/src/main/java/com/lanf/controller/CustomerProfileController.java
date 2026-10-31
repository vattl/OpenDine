package com.lanf.controller;

import com.lanf.entity.R;
import com.lanf.entity.User;
import com.lanf.service.CustomerProfileService;
import org.springframework.web.bind.annotation.*;
import org.springframework.web.multipart.MultipartFile;
import java.util.Map;

@RestController
@RequestMapping("/order")
public class CustomerProfileController {
    private final CustomerProfileService profiles;
    public CustomerProfileController(CustomerProfileService profiles) { this.profiles = profiles; }
    @PostMapping("/updateUser")
    public R updateUser(@RequestBody User user) { return profiles.updateUser(user); }
    @PostMapping("/getUserInfo")
    public R getUserInfo(@RequestBody Map<String,String> params) { return profiles.getUserInfo(params); }
    @PostMapping("/updateAvatar")
    public R updateAvatar(@RequestParam(value="phone",required=false) String phone,
                          @RequestParam(value="nickname",required=false) String nickname,
                          @RequestParam(value="openid",required=false) String openid,
                          @RequestParam(value="avatar",required=false) MultipartFile avatar) {
        return profiles.updateAvatar(phone,nickname,openid,avatar);
    }
}
