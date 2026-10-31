package com.lanf.service;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.lanf.entity.User;
import com.lanf.entity.R;
import org.springframework.stereotype.Service;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.web.multipart.MultipartFile;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import java.util.*;
import java.io.IOException;

/** Shared profile behavior for HTTP and AI callers; identity policy stays at the existing boundary. */
@Service
public class CustomerProfileService {
    private static final Logger log = LoggerFactory.getLogger(CustomerProfileService.class);
    @Autowired private IUserService userService;
    @Autowired private ICouponService CouponService;
    @Autowired private ObjectMapper objectMapper;
    @Value("${avatarImgsFilePath}") private String avatarImgsFilePath;
    /**
     * 更新用户信息接口（昵称和头像）
     */
    public R updateUser(User userInfo) {
        try {
            // 日志输出关键参数，便于调试

            // 参数校验：openid和phone不能同时为空
            if ((userInfo.getOpenid() == null || userInfo.getOpenid().trim().isEmpty())) {
                return R.error("用户标识不能为空（openid或phone）");
            }

            // 获取用户（优先使用openid，其次使用phone）
            User user = null;
            if (!userInfo.getOpenid().trim().isEmpty()) {
                user = userService.getUserByOpenid(userInfo.getOpenid());
            }



            if (user == null) return R.error("用户不存在");

            // 更新用户信息（只更新不为空的字段）
            boolean hasUpdate = false;

            // 处理昵称更新（兼容 nickname 与 name）
            String customNickname = userInfo.getNickname() != null && !userInfo.getNickname().trim().isEmpty()
                    ? userInfo.getNickname().trim()
                    : (userInfo.getName() != null && !userInfo.getName().trim().isEmpty() ? userInfo.getName().trim() : null);
            if (customNickname != null && !customNickname.isEmpty()) {
                user.setName(customNickname);
                hasUpdate = true;
            }

            // 处理手机号更新（如果存在）
            if (userInfo.getPhone() != null && !userInfo.getPhone().trim().isEmpty() &&
                    (user.getPhone() == null || !user.getPhone().equals(userInfo.getPhone().trim()))) {
                user.setPhone(userInfo.getPhone().trim());
                hasUpdate = true;
            }

            // 处理生日：仅允许设置一次，已有生日则不可再修改
            if (userInfo.getBirthday() != null && !userInfo.getBirthday().trim().isEmpty()) {
                String birthdayVal = userInfo.getBirthday().trim();
                if (user.getBirthday() == null || user.getBirthday().trim().isEmpty()) {
                    user.setBirthday(birthdayVal);
                    hasUpdate = true;
                }
            }

            // 执行更新
            if (hasUpdate) {
                //user.setUpdateTime(new Date());
                userService.updateById(user);
            }

            // 返回更新后的用户信息
            Map<String, Object> result = new HashMap<>();
            result.put("nickname", user.getName());
            result.put("avatar", user.getAvatar());
            result.put("phone", user.getPhone());
            result.put("points", user.getPoints());
            result.put("birthday", user.getBirthday());

            return R.ok().put("data", result);

        } catch (Exception e) {
            log.error("更新用户信息失败 type={}", e.getClass().getSimpleName());
            return R.error("更新用户信息失败");
        }
    }

    /**
     * 更新用户信息接口（昵称和头像）
     */
    public R updateAvatar(
            String phone,
            String nickname,
            String openid,
            MultipartFile avatarFile) {
        try {
            // 日志输出关键参数，便于调试

            // 参数校验：openid和phone不能同时为空
            if ((openid == null || openid.trim().isEmpty()))  {
                return R.error("用户标识不能为空（openid或phone）");
            }

            // 获取用户（优先使用openid，其次使用phone）
            User user = null;
            if (openid != null && !openid.trim().isEmpty()) {
                user = userService.getUserByOpenid(openid);
            }

            if (user == null) return R.error("用户不存在");

            // 更新用户信息（只更新不为空的字段）
            boolean hasUpdate = false;


            // 处理昵称更新
            if (nickname != null && !nickname.trim().isEmpty()) {
                user.setName(nickname.trim());
                hasUpdate = true;
            }

            // 处理头像上传
            if (avatarFile != null && !avatarFile.isEmpty()) {
                String avatarUrl = uploadAvatarFile(avatarFile);
                if (avatarUrl != null) {
                    user.setAvatar(avatarUrl);
                    hasUpdate = true;
                }
            }

            // 执行更新
            if (hasUpdate) {
                //user.setUpdateTime(new Date());
                userService.updateById(user);
            }

            // 返回更新后的用户信息
            Map<String, Object> result = new HashMap<>();
            result.put("nickname", user.getName());
            result.put("avatar", user.getAvatar());
            result.put("phone", user.getPhone());
            result.put("points", user.getPoints());

            return R.ok().put("data", result);

        } catch (Exception e) {
            log.error("更新用户信息失败 type={}", e.getClass().getSimpleName());
            return R.error("更新用户信息失败");
        }
    }


    // 修改文件上传方法，确保目录存在
    private String uploadAvatarFile(MultipartFile file) throws IOException {
        return com.lanf.service.ImageSafety.storeAvatar(file, avatarImgsFilePath);
    }

    public R getUserInfo(Map<String, String> params){
        String openid = params.get("openid");
        if (openid == null || openid.trim().isEmpty()) {
            return R.error("openid不能为空");
        }
        User user = userService.getUserByOpenid(openid);
        if (user == null) {
            return R.error("用户不存在");
        }
        int couponCount = CouponService.getAvailableCouponCount(openid);
        Map<String, Object> data = objectMapper.convertValue(user, Map.class);
        data.put("couponCount", couponCount);
        data.put("nickname", user.getName());
        return R.ok().put("data", data);
    }


}
