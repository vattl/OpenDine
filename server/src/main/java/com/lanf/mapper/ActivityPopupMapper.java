package com.lanf.mapper;

import com.baomidou.mybatisplus.core.conditions.query.QueryWrapper;
import com.baomidou.mybatisplus.core.mapper.BaseMapper;
import com.lanf.entity.ActivityPopup;
import com.lanf.entity.Banner;
import com.lanf.entity.User;
import org.apache.ibatis.annotations.Mapper;
import org.apache.ibatis.annotations.Param;
import org.apache.ibatis.annotations.Update;

import java.util.List;

/**
 * 活动弹窗数据访问接口
 */
@Mapper
public interface ActivityPopupMapper extends BaseMapper<ActivityPopup> {
    List<ActivityPopup> selectEnabledPopup();
    public List<ActivityPopup> selectAllPopup();

}
