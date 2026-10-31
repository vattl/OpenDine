package com.lanf.service.impl;

import com.baomidou.mybatisplus.core.conditions.query.QueryWrapper;
import com.baomidou.mybatisplus.core.conditions.update.UpdateWrapper;
import com.baomidou.mybatisplus.extension.service.impl.ServiceImpl;
import com.lanf.entity.UserAddress;
import com.lanf.mapper.UserAddressMapper;
import com.lanf.service.IUserAddressService;
import com.lanf.util.CoordinateNormalizer;
import org.springframework.stereotype.Service;
import org.springframework.util.StringUtils;

import java.util.Date;
import java.util.List;

@Service
public class UserAddressServiceImpl extends ServiceImpl<UserAddressMapper, UserAddress> implements IUserAddressService {

    @Override
    public List<UserAddress> listByOpenid(String openid) {
        if (!StringUtils.hasText(openid)) {
            return java.util.Collections.emptyList();
        }
        return list(new QueryWrapper<UserAddress>()
                .eq("openid", openid.trim())
                .orderByDesc("is_default")
                .orderByDesc("id"));
    }

    @Override
    public UserAddress getByIdAndOpenid(Long id, String openid) {
        if (id == null || !StringUtils.hasText(openid)) {
            return null;
        }
        UserAddress u = getById(id);
        if (u == null || u.getOpenid() == null || !openid.trim().equals(u.getOpenid().trim())) {
            return null;
        }
        return u;
    }

    @Override
    public boolean saveOrUpdateForUser(UserAddress row) {
        if (row == null || !StringUtils.hasText(row.getOpenid()) || !StringUtils.hasText(row.getContact_phone())
                || !StringUtils.hasText(row.getDetail_address())) {
            return false;
        }
        row.setOpenid(row.getOpenid().trim());
        normalizeCoordinates(row);
        Date now = new Date();
        if (row.getId() == null) {
            row.setCreated_at(now);
        }
        if (row.getIs_default() != null && row.getIs_default() == 1) {
            update(new UpdateWrapper<UserAddress>()
                    .set("is_default", 0)
                    .eq("openid", row.getOpenid()));
        } else if (row.getIs_default() == null) {
            long cnt = count(new QueryWrapper<UserAddress>().eq("openid", row.getOpenid()));
            if (cnt == 0) {
                row.setIs_default(1);
                update(new UpdateWrapper<UserAddress>().set("is_default", 0).eq("openid", row.getOpenid()));
            } else {
                row.setIs_default(0);
            }
        }
        return saveOrUpdate(row);
    }

    private static void normalizeCoordinates(UserAddress row) {
        if (row.getLat() == null && row.getLng() == null) {
            return;
        }
        if (row.getLat() == null || row.getLng() == null) {
            throw new IllegalArgumentException("经度 lng 与纬度 lat 必须同时提供");
        }
        CoordinateNormalizer.Point point = CoordinateNormalizer.toGcj02(
                row.getLat().doubleValue(), row.getLng().doubleValue(), row.getCoordinate_type());
        row.setLat(CoordinateNormalizer.decimal(point.getLat()));
        row.setLng(CoordinateNormalizer.decimal(point.getLng()));
        row.setCoordinate_type(CoordinateNormalizer.GCJ02);
    }

    @Override
    public boolean removeByIdAndOpenid(Long id, String openid) {
        UserAddress u = getByIdAndOpenid(id, openid);
        return u != null && removeById(id);
    }

    @Override
    public boolean setDefault(Long id, String openid) {
        UserAddress u = getByIdAndOpenid(id, openid);
        if (u == null) {
            return false;
        }
        update(new UpdateWrapper<UserAddress>().set("is_default", 0).eq("openid", u.getOpenid()));
        u.setIs_default(1);
        return updateById(u);
    }
}
