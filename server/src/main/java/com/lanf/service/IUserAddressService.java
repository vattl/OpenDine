package com.lanf.service;

import com.baomidou.mybatisplus.extension.service.IService;
import com.lanf.entity.UserAddress;

import java.util.List;

public interface IUserAddressService extends IService<UserAddress> {

    List<UserAddress> listByOpenid(String openid);

    UserAddress getByIdAndOpenid(Long id, String openid);

    boolean saveOrUpdateForUser(UserAddress row);

    boolean removeByIdAndOpenid(Long id, String openid);

    boolean setDefault(Long id, String openid);
}
