package com.lanf.mapper;

import com.baomidou.mybatisplus.core.mapper.BaseMapper;
import com.lanf.entity.Banner;
import java.util.List;

/**
 * 轮播图数据访问接口
 */
public interface BannerMapper extends BaseMapper<Banner> {

    /**
     * 查询所有启用的轮播图
     * @return 轮播图列表
     */
    List<Banner> selectEnabledBanners();

    /**
     * 查询所有轮播图
     * @return 轮播图列表
     */
    List<Banner> selectAllBanners();
}
