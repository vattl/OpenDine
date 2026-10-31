package com.lanf.user;

import com.baomidou.mybatisplus.core.conditions.query.QueryWrapper;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.lanf.entity.R;
import com.lanf.entity.User;
import com.lanf.mapper.UserMapper;
import com.lanf.service.CustomerProfileService;
import com.lanf.service.ICouponService;
import com.lanf.service.impl.IUserServiceImpl;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;
import org.springframework.test.util.ReflectionTestUtils;

import java.util.Date;
import java.util.HashMap;
import java.util.Map;

import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.*;

class UserRegistrationNicknameTest {

    private IUserServiceImpl userService;
    private UserMapper userMapper;
    private CustomerProfileService customerProfileService;
    private ICouponService couponService;

    @BeforeEach
    void setUp() {
        userService = new IUserServiceImpl();
        userMapper = mock(UserMapper.class);
        ReflectionTestUtils.setField(userService, "baseMapper", userMapper);
        ReflectionTestUtils.setField(userService, "UserMapper", userMapper);

        customerProfileService = new CustomerProfileService();
        couponService = mock(ICouponService.class);
        ReflectionTestUtils.setField(customerProfileService, "userService", userService);
        ReflectionTestUtils.setField(customerProfileService, "CouponService", couponService);
        ReflectionTestUtils.setField(customerProfileService, "objectMapper", new ObjectMapper());
    }

    @Test
    void testNewUserRegistration_AssignsDefaultNickname() {
        User newUser = new User();
        newUser.setOpenid("wx_new_001");

        when(userMapper.insert(any(User.class))).thenAnswer(invocation -> {
            User u = invocation.getArgument(0);
            u.setId(10086);
            return 1;
        });

        boolean result = userService.save(newUser);

        assertTrue(result);
        assertEquals(10086, newUser.getId());
        assertEquals("老肥吃货10086", newUser.getName());
        assertEquals("老肥吃货10086", newUser.getNickname());
        verify(userMapper).insert(newUser);
        verify(userMapper).updateById(newUser);
    }

    @Test
    void testNewUserRegistration_ExplicitNicknamePreserved() {
        User newUser = new User();
        newUser.setOpenid("wx_new_002");
        newUser.setName("显式自定义昵称");

        when(userMapper.insert(any(User.class))).thenAnswer(invocation -> {
            User u = invocation.getArgument(0);
            u.setId(10087);
            return 1;
        });

        boolean result = userService.save(newUser);

        assertTrue(result);
        assertEquals(10087, newUser.getId());
        assertEquals("显式自定义昵称", newUser.getName());
        assertEquals("显式自定义昵称", newUser.getNickname());
        verify(userMapper).insert(newUser);
        verify(userMapper, never()).updateById(newUser);
    }

    @Test
    void testUpdateUser_ModifiesNickname() {
        User existingUser = new User();
        existingUser.setId(10088);
        existingUser.setOpenid("wx_update_001");
        existingUser.setName("老肥吃货10088");

        when(userMapper.selectByOpenid("wx_update_001")).thenReturn(existingUser);

        User updateReq = new User();
        updateReq.setOpenid("wx_update_001");
        updateReq.setNickname("饕餮客");

        R r = customerProfileService.updateUser(updateReq);

        assertEquals(0, r.get("code"));
        assertEquals("饕餮客", existingUser.getName());
        assertEquals("饕餮客", existingUser.getNickname());
        verify(userMapper).updateById(existingUser);

        @SuppressWarnings("unchecked")
        Map<String, Object> data = (Map<String, Object>) r.get("data");
        assertEquals("饕餮客", data.get("nickname"));
    }

    @Test
    void testUpdateAvatar_ModifiesNickname() {
        User existingUser = new User();
        existingUser.setId(10089);
        existingUser.setOpenid("wx_avatar_001");
        existingUser.setName("老肥吃货10089");

        when(userMapper.selectByOpenid("wx_avatar_001")).thenReturn(existingUser);

        R r = customerProfileService.updateAvatar(null, "新食神", "wx_avatar_001", null);

        assertEquals(0, r.get("code"));
        assertEquals("新食神", existingUser.getName());
        verify(userMapper).updateById(existingUser);

        @SuppressWarnings("unchecked")
        Map<String, Object> data = (Map<String, Object>) r.get("data");
        assertEquals("新食神", data.get("nickname"));
    }

    @Test
    void testGetUserInfo_ReturnsBothNameAndNickname() {
        User existingUser = new User();
        existingUser.setId(10090);
        existingUser.setOpenid("wx_info_001");
        existingUser.setName("老肥吃货10090");

        when(userMapper.selectByOpenid("wx_info_001")).thenReturn(existingUser);
        when(couponService.getAvailableCouponCount("wx_info_001")).thenReturn(3);

        Map<String, String> params = new HashMap<>();
        params.put("openid", "wx_info_001");
        R r = customerProfileService.getUserInfo(params);

        assertEquals(0, r.get("code"));
        @SuppressWarnings("unchecked")
        Map<String, Object> data = (Map<String, Object>) r.get("data");
        assertEquals("老肥吃货10090", data.get("nickname"));
        assertEquals("老肥吃货10090", data.get("name"));
        assertEquals(3, data.get("couponCount"));
    }

    @Test
    void testBindPhone_DoesNotOverwriteExistingNickname() {
        User existingUser = new User();
        existingUser.setId(10091);
        existingUser.setOpenid("wx_bind_001");
        existingUser.setName("自定义不重置");

        when(userMapper.selectOne(any())).thenReturn(null); // phoneOwner not found
        // current user query
        when(userMapper.selectOne(argThat(qw -> qw != null))).thenReturn(existingUser);
        when(userMapper.selectById(10091)).thenReturn(existingUser);

        User bound = userService.bindPhoneToOpenid("wx_bind_001", "13800138000", "session123");

        assertNotNull(bound);
        assertEquals("自定义不重置", bound.getName());
        assertEquals("13800138000", bound.getPhone());
    }
}
