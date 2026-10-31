package com.lanf.ai.service.impl;

import com.baomidou.mybatisplus.core.conditions.query.QueryWrapper;
import com.fasterxml.jackson.core.type.TypeReference;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.lanf.ai.dto.AiMenuSnapshotDTO;
import com.lanf.ai.dto.AiMenuSnapshotDTO.AiMenuItemDTO;
import com.lanf.ai.entity.DishFoodProfile;
import com.lanf.ai.mapper.DishFoodProfileMapper;
import com.lanf.ai.service.IAiMenuAdapterService;
import com.lanf.entity.Category;
import com.lanf.entity.Dish;
import com.lanf.entity.DishShop;
import com.lanf.mapper.CategoryMapper;
import com.lanf.mapper.DishMapper;
import com.lanf.mapper.DishShopMapper;
import com.lanf.util.DishShopOverrides;
import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Service;
import org.springframework.util.DigestUtils;

import java.nio.charset.StandardCharsets;
import java.util.*;
import java.util.stream.Collectors;

@Slf4j
@Service
public class AiMenuAdapterServiceImpl implements IAiMenuAdapterService {

    @Autowired
    private DishMapper dishMapper;

    @Autowired
    private DishShopMapper dishShopMapper;

    @Autowired
    private DishFoodProfileMapper dishFoodProfileMapper;

    @Autowired(required = false)
    private CategoryMapper categoryMapper;

    private final ObjectMapper objectMapper = new ObjectMapper();

    @Override
    public AiMenuSnapshotDTO getStoreMenuSnapshot(Integer shopId) {
        int targetShopId = (shopId != null && shopId > 0) ? shopId : 1;

        // 1. 读取门店挂载及覆盖 (t_dish_shop) 并提取门店关联菜品 ID
        List<DishShop> shopOverlays = dishShopMapper.selectList(new QueryWrapper<DishShop>().eq("shop_id", targetShopId));
        Map<Integer, DishShop> overlayMap = new HashMap<>();
        if (shopOverlays != null) {
            for (DishShop ds : shopOverlays) {
                if (ds != null && ds.getDish_id() != null) {
                    overlayMap.put(ds.getDish_id(), ds);
                }
            }
        }

        // 2. 读取基础商品列表（若门店已配置挂载菜品，严格限定在门店挂载菜品内，杜绝串入其他门店专有菜品）
        List<Dish> baseDishes;
        if (!overlayMap.isEmpty()) {
            baseDishes = dishMapper.selectList(new QueryWrapper<Dish>().in("id", overlayMap.keySet()).orderByAsc("sorting"));
        } else {
            // 未配置独立门店菜单时回退总部/默认菜单
            baseDishes = dishMapper.selectList(new QueryWrapper<Dish>().orderByAsc("sorting"));
        }

        if (baseDishes == null || baseDishes.isEmpty()) {
            AiMenuSnapshotDTO empty = new AiMenuSnapshotDTO();
            empty.setShop_id(targetShopId);
            empty.setMenu_version(null);
            empty.setTimestamp(System.currentTimeMillis());
            empty.setItems(Collections.emptyList());
            return empty;
        }

        // 3. 应用门店个性化覆盖 (单价、库存、售罄、上下架)
        DishShopOverrides.apply(baseDishes, overlayMap);

        // 4. 读取分类映射
        Map<Integer, String> categoryMap = new HashMap<>();
        if (categoryMapper != null) {
            try {
                List<Category> categories = categoryMapper.selectList(null);
                if (categories != null) {
                    for (Category c : categories) {
                        if (c != null && c.getId() != null) {
                            categoryMap.put(c.getId(), c.getLabel());
                        }
                    }
                }
            } catch (Exception e) {
                log.warn("Query category failed: {}", e.getMessage());
            }
        }

        // 5. 读取食材与风味扩展画像 (t_dish_food_profile)
        List<DishFoodProfile> profiles = dishFoodProfileMapper.selectList(
                new QueryWrapper<DishFoodProfile>().eq("shop_id", targetShopId));
        Map<Integer, DishFoodProfile> profileMap = new HashMap<>();
        if (profiles != null) {
            for (DishFoodProfile p : profiles) {
                if (p != null && p.getDish_id() != null) {
                    profileMap.put(p.getDish_id(), p);
                }
            }
        }

        // 6. 组装规范化 AiMenuItemDTO 列表（严格过滤下架菜品）
        List<AiMenuItemDTO> dtoList = new ArrayList<>();
        StringBuilder hashDigestBuilder = new StringBuilder();

        for (Dish dish : baseDishes) {
            if (dish == null || dish.getId() == null) {
                continue;
            }
            if (!dish.isOnsale()) {
                continue;
            }

            AiMenuItemDTO item = new AiMenuItemDTO();
            item.setDish_id(dish.getId());
            item.setName(dish.getName());
            item.setCategory_name(categoryMap.get(dish.getTypeId()));
            item.setUnit(dish.getUnit() != null ? dish.getUnit() : "份");
            item.setActive(dish.isOnsale());
            item.setSold_out(dish.getSold_out() != null && dish.getSold_out() == 1);
            item.setStock(dish.getStock());
            item.setMonthlysale(dish.getMonthlysale() != null ? dish.getMonthlysale() : 0);
            item.setSales_count(item.getMonthlysale());
            item.setImage(dish.getImage());

            // 价格转换为整数分
            int priceFen = 0;
            if (dish.getUnitprice() != null) {
                priceFen = Math.round(dish.getUnitprice() * 100);
            }
            item.setPrice_fen(priceFen);

            // 附加扩展画像
            DishFoodProfile profile = profileMap.get(dish.getId());
            if (profile != null) {
                item.setNon_spicy_available(profile.getNon_spicy_available() != null && profile.getNon_spicy_available() == 1);
                item.setCross_contact_risk(profile.getCross_contact_risk() != null && profile.getCross_contact_risk() == 1);
                item.setIs_suitable_fitness(profile.getIs_suitable_fitness() != null && profile.getIs_suitable_fitness() == 1);
                item.setCalories_kcal(profile.getCalories_kcal());
                item.setProtein_g(profile.getProtein_g());
                item.setFat_g(profile.getFat_g());
                item.setEdible_weight_g(profile.getEdible_weight_g());
                item.setNutrition_source(profile.getNutrition_source());

                if (profile.getSpice_options() != null && !profile.getSpice_options().trim().isEmpty()) {
                    try {
                        List<String> opts = objectMapper.readValue(profile.getSpice_options(), new TypeReference<List<String>>() {});
                        item.setSpice_options(opts);
                    } catch (Exception ignored) {
                        item.setSpice_options(Arrays.asList("免辣", "微辣", "中辣"));
                    }
                }
                if (profile.getVerified_allergens() != null && !profile.getVerified_allergens().trim().isEmpty()) {
                    try {
                        List<String> allergens = objectMapper.readValue(profile.getVerified_allergens(), new TypeReference<List<String>>() {});
                        item.setVerified_allergens(allergens);
                    } catch (Exception ignored) {
                        item.setVerified_allergens(Collections.emptyList());
                    }
                }
            } else {
                // 默认降级处理：菜品默认支持免辣，无过敏原认证数据
                boolean nameImpliesSpicy = dish.getName() != null && (dish.getName().contains("辣") || dish.getName().contains("麻辣") || dish.getName().contains("泡椒"));
                item.setNon_spicy_available(!nameImpliesSpicy);
                item.setCross_contact_risk(false);
                item.setIs_suitable_fitness(false);
                item.setNutrition_source("UNVERIFIED");
                item.setSpice_options(Arrays.asList("免辣", "微辣", "中辣"));
                item.setVerified_allergens(Collections.emptyList());
            }

            dtoList.add(item);

            // 参与版本 Hash 计算 (ID:price:stock:onsale:sold_out)
            hashDigestBuilder.append(dish.getId()).append(":")
                    .append(priceFen).append(":")
                    .append(dish.getStock()).append(":")
                    .append(dish.isOnsale()).append(":")
                    .append(dish.getSold_out()).append(";");
        }

        // 计算当前菜单快照版本 Hash
        String versionHash = "v_" + DigestUtils.md5DigestAsHex(hashDigestBuilder.toString().getBytes(StandardCharsets.UTF_8));

        AiMenuSnapshotDTO snapshot = new AiMenuSnapshotDTO();
        snapshot.setShop_id(targetShopId);
        snapshot.setMenu_version(versionHash);
        snapshot.setTimestamp(System.currentTimeMillis());
        snapshot.setItems(dtoList);
        return snapshot;
    }
}
