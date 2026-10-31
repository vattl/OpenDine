package com.lanf.service;

import com.baomidou.mybatisplus.extension.service.IService;
import com.lanf.entity.Banner;
import java.util.List;

/**
 * 轮播图服务接口
 */
public interface IBannerService extends IService<Banner> {
    /**
     * 查询所有启用的轮播图
     * @return 轮播图列表
     */
    List<Banner> getAllBanners();
    /**
     * 查询所有启用的轮播图
     * @return 轮播图列表
     */
    List<Banner> getEnabledBanners();

    /**
     * 更新轮播图状态
     * @param id 轮播图ID
     * @param status 状态(0-禁用,1-启用)
     * @return 是否更新成功
     */
    boolean updateBannerStatus(Integer id, Integer status);

    /**
     * 添加轮播图
     * @param banner 轮播图信息
     * @return 是否添加成功
     */
    boolean addBanner(Banner banner);

    /**
     * 更新轮播图信息
     * @param banner 轮播图信息
     * @return 是否更新成功
     */
    boolean updateBannerInfo(Banner banner);

    /**
     * 批量删除轮播图
     * @param ids 轮播图ID列表
     * @return 删除的数量
     */
    int batchDeleteBanners(List<Integer> ids);
}
