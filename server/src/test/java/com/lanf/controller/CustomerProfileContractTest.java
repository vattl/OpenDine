package com.lanf.controller;

import com.lanf.entity.User;
import com.lanf.service.IUserService;
import org.junit.jupiter.api.Test;
import org.springframework.test.util.ReflectionTestUtils;
import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.Mockito.*;

class CustomerProfileContractTest {
    @Test void databaseDetailsNeverReachProfileResponse() {
        com.lanf.service.CustomerProfileService profiles = new com.lanf.service.CustomerProfileService();
        IUserService users = mock(IUserService.class);
        ReflectionTestUtils.setField(profiles,"userService",users);
        when(users.getUserByOpenid("profile-test")).thenThrow(new org.springframework.dao.DataAccessResourceFailureException("jdbc-secret-host SQL SELECT password"));
        User input = new User(); input.setOpenid("profile-test");
        String response = profiles.updateUser(input).toString();
        assertFalse(response.contains("jdbc-secret-host"));
        assertFalse(response.contains("SELECT password"));
    }
    @Test void birthdayRemainsWriteOnceAndNicknameCanChange() {
        com.lanf.service.CustomerProfileService controller = new com.lanf.service.CustomerProfileService();
        IUserService users = mock(IUserService.class);
        ReflectionTestUtils.setField(controller,"userService",users);
        User persisted = new User(); persisted.setBirthday("2000-01-01");
        when(users.getUserByOpenid("profile-test")).thenReturn(persisted);
        User input = new User(); input.setOpenid("profile-test");
        input.setName(" New name "); input.setBirthday("2001-02-02");
        assertEquals(0,controller.updateUser(input).get("code"));
        assertEquals("2000-01-01",persisted.getBirthday());
        assertEquals("New name",persisted.getName());
        verify(users).updateById(persisted);
    }
}
