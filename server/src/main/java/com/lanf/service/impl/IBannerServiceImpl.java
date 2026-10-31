package com.lanf.service.impl;

import com.baomidou.mybatisplus.extension.service.impl.ServiceImpl;
import com.lanf.entity.Banner;
import com.lanf.mapper.BannerMapper;
import com.lanf.service.IBannerService;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import java.util.List;

/**
 * 轮播图服务实现类
 */
@Service
public class IBannerServiceImpl extends ServiceImpl<BannerMapper, Banner> implements IBannerService {

    @Override
    public List<Banner> getAllBanners() {
        // 调用Mapper方法查询所有启用状态的轮播图
        return baseMapper.selectAllBanners();
    }
    @Override
    public List<Banner> getEnabledBanners() {
        // 调用Mapper方法查询所有启用状态的轮播图
        return baseMapper.selectEnabledBanners();
    }
    @Override
    @Transactional
    public boolean updateBannerStatus(Integer id, Integer status) {
        // 参数校验
        if (id == null || status == null || (status != 0 && status != 1)) {
            return false;
        }

        Banner banner = new Banner();
        banner.setId(id);
        banner.setStatus(status);
        return updateById(banner);
    }

    @Override
    @Transactional
    public boolean addBanner(Banner banner) {
        // 参数校验
        if (banner == null ||
                (banner.getImage() == null || banner.getImage().trim().isEmpty())) {
            return false;
        }

        // 设置默认状态为启用
        if (banner.getStatus() == null) {
            banner.setStatus(1);
        }

        return save(banner);
    }

    @Override
    @Transactional
    public boolean updateBannerInfo(Banner banner) {
        // 参数校验
        if (banner == null || banner.getId() == null) {
            return false;
        }

        return updateById(banner);
    }

    @Override
    @Transactional
    public int batchDeleteBanners(List<Integer> ids) {
        if (ids == null || ids.isEmpty()) {
            return 0;
        }

        return baseMapper.deleteBatchIds(ids);
    }
}
