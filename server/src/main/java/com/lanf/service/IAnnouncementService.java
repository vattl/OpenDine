package com.lanf.service;

import com.baomidou.mybatisplus.extension.service.IService;
import com.lanf.entity.Announcement;

import java.util.List;

public interface IAnnouncementService extends IService<Announcement> {

    /**
     * C 端：当前门店可见且启用、且在有效时间内的公告。
     */
    List<Announcement> listEnabledForShop(Integer shopId);

    /**
     * B 端列表：无门店上下文时返回全部；有门店时返回「全店 + 本店」。
     */
    List<Announcement> listForAdmin(Integer resolvedShopId, Integer status);

    /**
     * 门店账号是否允许维护该行（null 表示全部门店公告，仅无门店上下文/HQ 场景允许写）。
     */
    boolean canWriteRow(Announcement row, Integer resolvedShopId);
}
