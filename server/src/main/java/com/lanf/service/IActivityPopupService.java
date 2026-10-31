package com.lanf.service;

import com.baomidou.mybatisplus.extension.service.IService;
import com.lanf.entity.ActivityPopup;
import com.lanf.entity.User;
import org.springframework.transaction.annotation.Transactional;

import java.util.List;

/**
 * 活动弹窗服务接口
 */
public interface IActivityPopupService extends IService<ActivityPopup> {

    List<ActivityPopup> getAllPopup();
    List<ActivityPopup> getEnabledPopup();
    /**
     * 获取点餐页面的有效活动弹窗
     * @param is_enabled 用户ID
     * @param userType 用户类型(all/new/member)
     * @return 有效的活动弹窗，无则返回null
     */
    List<ActivityPopup> getValidDiningPopupList(Integer is_enabled, int userType, String type, Integer shopId);

    ActivityPopup getValidDiningPopup(Integer is_enabled, int userType, String type, Integer shopId);








}
