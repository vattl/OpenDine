package com.lanf.service.impl;

import com.baomidou.mybatisplus.core.conditions.query.QueryWrapper;
import com.baomidou.mybatisplus.extension.service.impl.ServiceImpl;
import com.lanf.entity.Announcement;
import com.lanf.mapper.AnnouncementMapper;
import com.lanf.service.IAnnouncementService;
import org.springframework.stereotype.Service;

import java.util.Date;
import java.util.List;

@Service
public class AnnouncementServiceImpl extends ServiceImpl<AnnouncementMapper, Announcement> implements IAnnouncementService {

    @Override
    public List<Announcement> listEnabledForShop(Integer shopId) {
        Date now = new Date();
        QueryWrapper<Announcement> q = new QueryWrapper<>();
        q.eq("status", 1);
        if (shopId != null) {
            q.and(w -> w.isNull("shop_id").or().eq("shop_id", shopId));
        } else {
            q.isNull("shop_id");
        }
        q.and(w -> w.isNull("start_time").or().le("start_time", now));
        q.and(w -> w.isNull("end_time").or().ge("end_time", now));
        q.orderByAsc("sort_order").orderByDesc("id");
        return list(q);
    }

    @Override
    public List<Announcement> listForAdmin(Integer resolvedShopId, Integer status) {
        QueryWrapper<Announcement> q = new QueryWrapper<>();
        if (status != null) {
            q.eq("status", status);
        }
        if (resolvedShopId != null) {
            q.and(w -> w.isNull("shop_id").or().eq("shop_id", resolvedShopId));
        }
        q.orderByAsc("sort_order").orderByDesc("id");
        return list(q);
    }

    @Override
    public boolean canWriteRow(Announcement row, Integer resolvedShopId) {
        if (row == null) {
            return false;
        }
        if (resolvedShopId == null) {
            return true;
        }
        Integer sid = row.getShop_id();
        if (sid == null) {
            return false;
        }
        return sid.equals(resolvedShopId);
    }
}
