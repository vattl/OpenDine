package com.lanf.service.impl;

import com.baomidou.mybatisplus.core.conditions.query.QueryWrapper;
import com.baomidou.mybatisplus.extension.service.impl.ServiceImpl;
import com.lanf.entity.Shop;
import com.lanf.mapper.ShopMapper;
import com.lanf.service.IShopService;
import org.springframework.stereotype.Service;
import org.springframework.util.StringUtils;

@Service
public class ShopServiceImpl extends ServiceImpl<ShopMapper, Shop> implements IShopService {

    @Override
    public Integer requireActiveShopIdByCode(String code) {
        if (!StringUtils.hasText(code)) {
            return null;
        }
        String trimmed = code.trim();
        Shop one = getOne(new QueryWrapper<Shop>().eq("code", trimmed));
        if (one == null) {
            throw new RuntimeException("门店编码不存在");
        }
        if (one.getStatus() == null || one.getStatus() != 1) {
            throw new RuntimeException("门店不可用或不存在");
        }
        return one.getId();
    }
}
