package com.lanf.service.impl;

import com.baomidou.mybatisplus.core.conditions.query.QueryWrapper;
import com.baomidou.mybatisplus.extension.service.impl.ServiceImpl;
import com.lanf.entity.ActivityPopup;
import com.lanf.entity.Banner;
import com.lanf.entity.Order;
import com.lanf.entity.UserActivityInteraction;
import com.lanf.mapper.ActivityPopupMapper;
import com.lanf.service.IActivityPopupService;
import com.lanf.service.IOrderService;
import com.lanf.service.IUserActivityInteractionService;
import com.lanf.util.ActivityPopupShopFilter;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.util.Calendar;
import java.util.Date;
import java.util.List;
import java.util.stream.Collectors;

/**
 * 活动弹窗服务实现类
 */
@Service
@RequiredArgsConstructor
public class IActivityPopupServiceImpl extends ServiceImpl<ActivityPopupMapper, ActivityPopup> implements IActivityPopupService {

    private final IOrderService orderService;
    private final IUserActivityInteractionService userActivityInteractionService; // 注入的服务实例

    @Override
    public List<ActivityPopup> getEnabledPopup() {
        // 调用Mapper方法查询所有启用状态的轮播图
        return baseMapper.selectEnabledPopup();
    }
    @Override
    public List<ActivityPopup> getAllPopup() {
        // 调用Mapper方法查询所有启用状态的轮播图
        return baseMapper.selectAllPopup();
    }
    /**
     * 获取有效的点餐页面活动弹窗
     */
    @Transactional(readOnly = true)
    @Override
    public List<ActivityPopup> getValidDiningPopupList(Integer is_enabled, int userType, String type, Integer shopId) {
        Date now = new Date();

        QueryWrapper<ActivityPopup> queryWrapper = new QueryWrapper<>();
        queryWrapper.eq("is_enabled", 1)
                .eq("type", type)
                .and(wrapper -> wrapper
                        .eq("target_user", determineUserTypeByRegTime(userType))
                        .or()
                        .eq("target_user", "all")
                )
                .le("start_time", now)
                .ge("end_time", now);
        queryWrapper.orderByDesc("sorting").orderByDesc("created_at");

        return filterByShop(baseMapper.selectList(queryWrapper), shopId);
    }
    /**
     * 获取有效的点餐页面活动弹窗
     */
    @Transactional(readOnly = true)
    @Override
    public ActivityPopup getValidDiningPopup(Integer is_enabled, int userType, String type, Integer shopId) {
        Date now = new Date();

        QueryWrapper<ActivityPopup> queryWrapper = new QueryWrapper<>();
        queryWrapper.eq("is_enabled", 1)
                .eq("type", type)
                .and(wrapper -> wrapper
                        .eq("target_user", determineUserTypeByRegTime(userType))
                        .or()
                        .eq("target_user", "all")
                )
                .le("start_time", now)
                .ge("end_time", now);
        queryWrapper.orderByDesc("created_at").last("limit 1");

        List<ActivityPopup> matched = filterByShop(baseMapper.selectList(queryWrapper), shopId);
        return matched.isEmpty() ? null : matched.get(0);
    }

    private static List<ActivityPopup> filterByShop(List<ActivityPopup> list, Integer shopId) {
        if (list == null || list.isEmpty()) {
            return list;
        }
        return list.stream()
                .filter(p -> shopId != null
                        ? ActivityPopupShopFilter.appliesToShop(p.getApply_shop_ids(), shopId)
                        : ActivityPopupShopFilter.isGlobalScope(p.getApply_shop_ids()))
                .collect(Collectors.toList());
    }
    /**
     * 通过注册时间判断用户类型
     *
     * @return "new" 新用户 / "old" 老用户
     */
    private String determineUserTypeByRegTime(int userType) {


        return userType == 0 ? "new" : "old";
    }

    /**
     * 判断用户是否有历史订单
     */
    private boolean hasUserOrder(Long userId) {
        QueryWrapper<Order> queryWrapper = new QueryWrapper<>();
        queryWrapper.eq("user_id", userId)
                .ne("transac_status", "cancelled");
        return orderService.count(queryWrapper) > 0;
    }

    /**
     * 判断用户今日是否已关闭过该活动
     */
    private boolean hasUserClosedToday(Long userId, Long popupId) {
        // 获取今日开始时间
        Calendar calendar = Calendar.getInstance();
        calendar.set(Calendar.HOUR_OF_DAY, 0);
        calendar.set(Calendar.MINUTE, 0);
        calendar.set(Calendar.SECOND, 0);
        Date todayStart = calendar.getTime();

        // 获取今日结束时间
        calendar.set(Calendar.HOUR_OF_DAY, 23);
        calendar.set(Calendar.MINUTE, 59);
        calendar.set(Calendar.SECOND, 59);
        Date todayEnd = calendar.getTime();

        QueryWrapper<UserActivityInteraction> queryWrapper = new QueryWrapper<>();
        queryWrapper.eq("user_id", userId)
                .eq("activity_id", popupId)
                .eq("interaction_type", "close")
                .between("interaction_time", todayStart, todayEnd);

        // 修正：使用注入的服务实例调用count方法
        return userActivityInteractionService.count(queryWrapper) > 0;
    }
}
