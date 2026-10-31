package com.lanf.kds.service;

import com.baomidou.mybatisplus.core.conditions.query.QueryWrapper;
import com.lanf.kds.KdsScreenTag;
import com.lanf.kds.entity.KdsStation;
import com.lanf.kds.entity.KdsStationCategory;
import com.lanf.kds.entity.KdsDishScreen;
import com.lanf.kds.mapper.KdsDishScreenMapper;
import com.lanf.kds.mapper.KdsStationCategoryMapper;
import com.lanf.kds.mapper.KdsStationMapper;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Service;
import org.springframework.util.StringUtils;
import org.springframework.transaction.annotation.Transactional;

import java.util.ArrayList;
import java.util.Date;
import java.util.List;

@Service
public class KdsStationService {

    @Autowired
    private KdsStationMapper stationMapper;
    @Autowired
    private KdsStationCategoryMapper stationCategoryMapper;
    @Autowired
    private KdsDishScreenMapper dishScreenMapper;

    public List<KdsStation> listByShop(int shopId) {
        return stationMapper.selectList(new QueryWrapper<KdsStation>()
                .eq("shop_id", shopId)
                .orderByAsc("sort")
                .orderByAsc("id"));
    }

    public KdsStation getById(long id) {
        return stationMapper.selectById(id);
    }

    public KdsStation save(int shopId, KdsStation station) {
        if (station.getScreen_tag() != null && !KdsScreenTag.isValid(station.getScreen_tag())) {
            throw new IllegalArgumentException("无效的 screen_tag");
        }
        station.setShop_id(shopId);
        if (station.getEnabled() == null) {
            station.setEnabled(1);
        }
        if (station.getSort() == null) {
            station.setSort(0);
        }
        station.setUpdated_at(new Date());
        if (station.getId() == null) {
            if (!StringUtils.hasText(station.getCode())) {
                station.setCode(defaultCode(station.getScreen_tag(), station.getName()));
            }
            station.setCreated_at(new Date());
            stationMapper.insert(station);
        } else {
            KdsStation existing = stationMapper.selectById(station.getId());
            if (existing == null || !shopIdEquals(existing.getShop_id(), shopId)) {
                throw new IllegalArgumentException("档口不存在或不属于当前门店");
            }
            if (!StringUtils.hasText(station.getCode())) {
                station.setCode(existing.getCode());
            }
            stationMapper.updateById(station);
        }
        return stationMapper.selectById(station.getId());
    }

    /** code 为空时自动生成：标准五屏用预设编码，其余用 screen_tag 大写（去下划线）；均无则报错。 */
    static String defaultCode(String screenTag, String name) {
        if (screenTag != null) {
            for (KdsScreenTag.FiveScreenSeed seed : KdsScreenTag.fiveScreenSeeds()) {
                if (seed.screenTag.equals(screenTag)) {
                    return seed.code;
                }
            }
            String norm = screenTag.trim().toUpperCase().replace("_", "");
            if (!norm.isEmpty()) {
                return norm;
            }
        }
        if (name != null) {
            String norm = name.trim().replaceAll("[^a-zA-Z0-9]", "").toUpperCase();
            if (!norm.isEmpty()) {
                return norm;
            }
        }
        throw new IllegalArgumentException("code 不能为空");
    }

    public void delete(int shopId, long stationId) {
        KdsStation s = stationMapper.selectById(stationId);
        if (s == null || !shopIdEquals(s.getShop_id(), shopId)) {
            throw new IllegalArgumentException("档口不存在");
        }
        stationCategoryMapper.delete(new QueryWrapper<KdsStationCategory>().eq("station_id", stationId));
        stationMapper.deleteById(stationId);
    }

    @Transactional
    public List<KdsStation> initFiveScreens(int shopId) {
        List<KdsStation> created = new ArrayList<>();
        for (KdsScreenTag.FiveScreenSeed seed : KdsScreenTag.fiveScreenSeeds()) {
            KdsStation existing = stationMapper.selectOne(new QueryWrapper<KdsStation>()
                    .eq("shop_id", shopId)
                    .eq("screen_tag", seed.screenTag)
                    .last("LIMIT 1"));
            if (existing != null) {
                created.add(existing);
                continue;
            }
            KdsStation s = new KdsStation();
            s.setShop_id(shopId);
            s.setCode(seed.code);
            s.setName(seed.name);
            s.setScreen_tag(seed.screenTag);
            s.setSort(seed.sort);
            s.setEnabled(1);
            s.setCreated_at(new Date());
            stationMapper.insert(s);
            created.add(s);
        }
        return created;
    }

    @Transactional
    public void bindCategories(long stationId, int shopId, List<String> cidList) {
        KdsStation station = requireStationForShop(stationId, shopId);
        stationCategoryMapper.delete(new QueryWrapper<KdsStationCategory>().eq("station_id", station.getId()));
        if (cidList == null || cidList.isEmpty()) {
            return;
        }
        for (String cid : cidList) {
            if (cid == null || cid.trim().isEmpty()) {
                continue;
            }
            KdsStationCategory row = new KdsStationCategory();
            row.setStation_id(station.getId());
            row.setCid(cid.trim());
            row.setCreated_at(new Date());
            stationCategoryMapper.insert(row);
        }
    }

    public List<KdsStationCategory> listCategories(long stationId, int shopId) {
        requireStationForShop(stationId, shopId);
        return stationCategoryMapper.selectList(new QueryWrapper<KdsStationCategory>()
                .eq("station_id", stationId));
    }

    @Transactional
    public void bindDishScreens(int shopId, String screenTag, List<Integer> dishIds) {
        if (!KdsScreenTag.isValid(screenTag)) {
            throw new IllegalArgumentException("无效的 screen_tag");
        }
        if (dishIds == null || dishIds.isEmpty()) {
            return;
        }
        Date now = new Date();
        for (Integer dishId : dishIds) {
            if (dishId == null || dishId <= 0) {
                continue;
            }
            KdsDishScreen row = dishScreenMapper.selectOne(new QueryWrapper<KdsDishScreen>()
                    .eq("shop_id", shopId)
                    .eq("dish_id", dishId)
                    .last("LIMIT 1"));
            if (row == null) {
                row = new KdsDishScreen();
                row.setShop_id(shopId);
                row.setDish_id(dishId);
                row.setScreen_tag(screenTag);
                row.setCreated_at(now);
                dishScreenMapper.insert(row);
            } else {
                row.setScreen_tag(screenTag);
                row.setUpdated_at(now);
                dishScreenMapper.updateById(row);
            }
        }
    }

    public List<KdsDishScreen> listDishScreens(int shopId, Integer dishId, String screenTag) {
        QueryWrapper<KdsDishScreen> q = new QueryWrapper<KdsDishScreen>().eq("shop_id", shopId);
        if (dishId != null) {
            q.eq("dish_id", dishId);
        }
        if (screenTag != null && !screenTag.isEmpty()) {
            q.eq("screen_tag", screenTag);
        }
        return dishScreenMapper.selectList(q);
    }

    public KdsStation requireStationForShop(long stationId, int shopId) {
        KdsStation station = stationMapper.selectById(stationId);
        if (station == null || !shopIdEquals(station.getShop_id(), shopId)) {
            throw new IllegalArgumentException("档口不存在或不属于当前门店");
        }
        return station;
    }

    public KdsStation findByScreenTag(int shopId, String screenTag) {
        KdsStation station = stationMapper.selectOne(new QueryWrapper<KdsStation>()
                .eq("shop_id", shopId)
                .eq("screen_tag", screenTag)
                .eq("enabled", 1)
                .last("LIMIT 1"));
        if (station == null) {
            Integer count = stationMapper.selectCount(new QueryWrapper<KdsStation>().eq("shop_id", shopId));
            if (count == null || count == 0) {
                try {
                    initFiveScreens(shopId);
                    station = stationMapper.selectOne(new QueryWrapper<KdsStation>()
                            .eq("shop_id", shopId)
                            .eq("screen_tag", screenTag)
                            .eq("enabled", 1)
                            .last("LIMIT 1"));
                } catch (Exception ignored) {
                }
            }
        }
        return station;
    }

    private static boolean shopIdEquals(Integer a, int b) {
        return a != null && a == b;
    }
}
