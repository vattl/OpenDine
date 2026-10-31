package com.lanf.admin;

import com.baomidou.mybatisplus.core.conditions.query.QueryWrapper;
import com.baomidou.mybatisplus.extension.plugins.pagination.Page;
import com.lanf.controller.admin.AdminOrderController;
import com.lanf.entity.R;
import com.lanf.entity.User;
import com.lanf.mapper.UserMapper;
import com.lanf.service.IUserService;
import com.lanf.service.impl.IUserServiceImpl;
import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;
import org.springframework.test.util.ReflectionTestUtils;

import java.util.Collections;

import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.*;

class AdminMemberValidFilterTest {

    @Test
    void getOneUserInfo_rejectsUserWithoutBoundPhone() {
        AdminOrderController controller = new AdminOrderController();
        IUserService userService = mock(IUserService.class);
        ReflectionTestUtils.setField(controller, "UserService", userService);

        // 1. null user / openid
        R nullRes = controller.getOneUserInfo(null);
        assertEquals(500, nullRes.get("code"));

        User emptyOpenid = new User();
        emptyOpenid.setOpenid("  ");
        R emptyRes = controller.getOneUserInfo(emptyOpenid);
        assertEquals(500, emptyRes.get("code"));

        // 2. User not found
        when(userService.getUserByOpenid("non_existent")).thenReturn(null);
        User queryNonExist = new User();
        queryNonExist.setOpenid("non_existent");
        R notFoundRes = controller.getOneUserInfo(queryNonExist);
        assertEquals(500, notFoundRes.get("code"));

        // 3. User without phone
        User anonUser = new User();
        anonUser.setOpenid("anon_openid");
        anonUser.setPhone(null);
        when(userService.getUserByOpenid("anon_openid")).thenReturn(anonUser);
        User queryAnon = new User();
        queryAnon.setOpenid("anon_openid");
        R anonRes = controller.getOneUserInfo(queryAnon);
        assertEquals(500, anonRes.get("code"));
        assertTrue(anonRes.get("msg").toString().contains("未绑定手机号"));

        // 4. User with empty phone
        User blankPhoneUser = new User();
        blankPhoneUser.setOpenid("blank_phone");
        blankPhoneUser.setPhone("   ");
        when(userService.getUserByOpenid("blank_phone")).thenReturn(blankPhoneUser);
        User queryBlank = new User();
        queryBlank.setOpenid("blank_phone");
        R blankRes = controller.getOneUserInfo(queryBlank);
        assertEquals(500, blankRes.get("code"));

        // 5. Valid member with phone
        User validUser = new User();
        validUser.setOpenid("valid_openid");
        validUser.setPhone("13800138000");
        validUser.setSession_key("sensitive_secret");
        when(userService.getUserByOpenid("valid_openid")).thenReturn(validUser);
        User queryValid = new User();
        queryValid.setOpenid("valid_openid");
        R validRes = controller.getOneUserInfo(queryValid);
        assertEquals(0, validRes.get("code"));
        User returnedUser = (User) validRes.get("user");
        assertNotNull(returnedUser);
        assertEquals("13800138000", returnedUser.getPhone());
        assertNull(returnedUser.getSession_key());
    }

    @Test
    @SuppressWarnings("unchecked")
    void pageUserList_and_getAllUsers_enforcePhoneBoundFilter() {
        IUserServiceImpl userService = new IUserServiceImpl();
        UserMapper userMapper = mock(UserMapper.class);
        ReflectionTestUtils.setField(userService, "baseMapper", userMapper);
        ReflectionTestUtils.setField(userService, "UserMapper", userMapper);

        when(userMapper.selectPage(any(), any())).thenReturn(new Page<>(1, 20));
        when(userMapper.selectList(any())).thenReturn(Collections.emptyList());

        // pageUserList
        userService.pageUserList(1, 20, "test");
        ArgumentCaptor<QueryWrapper<User>> pageCaptor = ArgumentCaptor.forClass(QueryWrapper.class);
        verify(userMapper).selectPage(any(), pageCaptor.capture());
        String pageSql = pageCaptor.getValue().getCustomSqlSegment();
        assertTrue(pageSql.contains("phone IS NOT NULL"));
        assertTrue(pageSql.contains("TRIM(phone)"));

        // getAllUsers
        userService.getAllUsers();
        ArgumentCaptor<QueryWrapper<User>> listCaptor = ArgumentCaptor.forClass(QueryWrapper.class);
        verify(userMapper).selectList(listCaptor.capture());
        String listSql = listCaptor.getValue().getCustomSqlSegment();
        assertTrue(listSql.contains("phone IS NOT NULL"));
        assertTrue(listSql.contains("TRIM(phone)"));
    }
}
