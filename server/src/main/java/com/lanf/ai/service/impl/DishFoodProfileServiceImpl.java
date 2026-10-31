package com.lanf.ai.service.impl;

import com.baomidou.mybatisplus.core.conditions.query.QueryWrapper;
import com.fasterxml.jackson.core.type.TypeReference;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.lanf.ai.dto.DishFoodProfileInputDTO;
import com.lanf.ai.dto.DishWithProfileVO;
import com.lanf.ai.entity.DishFoodProfile;
import com.lanf.ai.mapper.DishFoodProfileMapper;
import com.lanf.ai.service.IDishFoodProfileService;
import com.lanf.common.ApiException;
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
import org.springframework.transaction.annotation.Transactional;

import java.math.BigDecimal;
import java.util.*;
import java.util.stream.Collectors;

@Slf4j
@Service
public class DishFoodProfileServiceImpl implements IDishFoodProfileService {

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
    public List<DishWithProfileVO> getStoreDishProfiles(Integer shopId, Integer categoryId, Boolean configuredOnly) {
        int targetShopId = (shopId != null && shopId > 0) ? shopId : 1;

        // 1. 读取门店挂载及覆盖 (t_dish_shop)
        List<DishShop> overlays = dishShopMapper.selectList(
                new QueryWrapper<DishShop>().eq("shop_id", targetShopId));
        Map<Integer, DishShop> overlayMap = (overlays != null)
                ? overlays.stream().filter(o -> o.getDish_id() != null).collect(Collectors.toMap(DishShop::getDish_id, ds -> ds, (a, b) -> a))
                : Collections.emptyMap();

        // 2. 读取基础商品（若门店已配置挂载菜品，严格限定在门店挂载菜品集合内）
        List<Dish> baseDishes;
        if (!overlayMap.isEmpty()) {
            baseDishes = dishMapper.selectList(new QueryWrapper<Dish>().in("id", overlayMap.keySet()).orderByAsc("sorting"));
        } else {
            baseDishes = dishMapper.selectList(new QueryWrapper<Dish>().orderByAsc("sorting"));
        }
        if (baseDishes == null || baseDishes.isEmpty()) {
            return Collections.emptyList();
        }

        DishShopOverrides.apply(baseDishes, overlayMap);

        // 3. 分类字典
        Map<Integer, String> categoryNameMap = new HashMap<>();
        if (categoryMapper != null) {
            List<Category> categories = categoryMapper.selectList(null);
            if (categories != null) {
                for (Category c : categories) {
                    categoryNameMap.put(c.getId(), c.getLabel());
                }
            }
        }

        // 4. 读取已存在的画像
        List<DishFoodProfile> profiles = dishFoodProfileMapper.selectList(
                new QueryWrapper<DishFoodProfile>().eq("shop_id", targetShopId));
        Map<Integer, DishFoodProfile> profileMap = new HashMap<>();
        if (profiles != null) {
            for (DishFoodProfile p : profiles) {
                profileMap.put(p.getDish_id(), p);
            }
        }

        List<DishWithProfileVO> result = new ArrayList<>();
        for (Dish d : baseDishes) {
            if (categoryId != null && categoryId > 0) {
                if (d.getTypeId() == null || !d.getTypeId().equals(categoryId)) {
                    continue;
                }
            }

            DishFoodProfile profile = profileMap.get(d.getId());
            boolean hasProfile = (profile != null);

            if (configuredOnly != null) {
                if (configuredOnly && !hasProfile) {
                    continue;
                }
                if (!configuredOnly && hasProfile) {
                    continue;
                }
            }

            DishWithProfileVO vo = new DishWithProfileVO();
            vo.setDish_id(d.getId());
            vo.setDish_name(d.getName());
            vo.setCategory_id(d.getTypeId());
            vo.setCategory_name(categoryNameMap.getOrDefault(d.getTypeId(), "默认分类"));

            BigDecimal priceYuan = (d.getUnitprice() != null) ? BigDecimal.valueOf(d.getUnitprice()) : BigDecimal.ZERO;
            vo.setPrice(priceYuan);
            vo.setPrice_fen(priceYuan.multiply(BigDecimal.valueOf(100)).intValue());

            vo.setOnsale(d.isOnsale() ? 1 : 0);
            vo.setSold_out((d.getSold_out() != null && d.getSold_out() == 1) ? 1 : 0);
            vo.setHas_profile(hasProfile);
            vo.setProfile(profile);

            result.add(vo);
        }

        return result;
    }

    @Override
    public DishFoodProfile getDishProfile(Integer shopId, Integer dishId) {
        if (dishId == null || dishId <= 0) {
            throw new ApiException(400, "INVALID_DISH_ID", "菜品ID不能为空");
        }
        int targetShopId = (shopId != null && shopId > 0) ? shopId : 1;

        DishFoodProfile profile = dishFoodProfileMapper.selectOne(new QueryWrapper<DishFoodProfile>()
                .eq("dish_id", dishId)
                .eq("shop_id", targetShopId));
        if (profile == null && targetShopId != 1) {
            // 回退总店默认画像
            profile = dishFoodProfileMapper.selectOne(new QueryWrapper<DishFoodProfile>()
                    .eq("dish_id", dishId)
                    .eq("shop_id", 1));
        }
        return profile;
    }

    @Override
    @Transactional(rollbackFor = Exception.class)
    public DishFoodProfile saveOrUpdateProfile(DishFoodProfileInputDTO input) {
        if (input == null || input.getDish_id() == null) {
            throw new ApiException(400, "INVALID_PARAM", "菜品ID不能为空");
        }
        int targetShopId = (input.getShop_id() != null && input.getShop_id() > 0)
                ? input.getShop_id()
                : (input.getStore_id() != null && input.getStore_id() > 0 ? input.getStore_id() : 1);

        DishFoodProfile existing = dishFoodProfileMapper.selectOne(new QueryWrapper<DishFoodProfile>()
                .eq("dish_id", input.getDish_id())
                .eq("shop_id", targetShopId));

        DishFoodProfile record = (existing != null) ? existing : new DishFoodProfile();
        record.setDish_id(input.getDish_id());
        record.setShop_id(targetShopId);
        record.setIngredients(input.getIngredients());
        record.setSeasonings(input.getSeasonings());
        record.setNon_spicy_available(input.getNon_spicy_available() != null ? input.getNon_spicy_available() : 1);
        record.setCross_contact_risk(input.getCross_contact_risk() != null ? input.getCross_contact_risk() : 0);
        record.setIs_suitable_fitness(input.getIs_suitable_fitness() != null ? input.getIs_suitable_fitness() : 0);
        record.setCalories_kcal(input.getCalories_kcal());
        record.setProtein_g(input.getProtein_g());
        record.setFat_g(input.getFat_g());
        record.setEdible_weight_g(input.getEdible_weight_g());
        record.setNutrition_source(input.getNutrition_source() != null ? input.getNutrition_source() : "ESTIMATED");
        record.setVerified_at(new Date());

        try {
            if (input.getSpice_options() != null) {
                record.setSpice_options(objectMapper.writeValueAsString(input.getSpice_options()));
            } else if (existing == null) {
                record.setSpice_options("[\"不辣\",\"微辣\",\"中辣\"]");
            }

            if (input.getVerified_allergens() != null) {
                record.setVerified_allergens(objectMapper.writeValueAsString(input.getVerified_allergens()));
            } else if (existing == null) {
                record.setVerified_allergens("[]");
            }
        } catch (Exception e) {
            log.error("JSON序列化失败", e);
        }

        if (existing != null) {
            dishFoodProfileMapper.updateById(record);
        } else {
            dishFoodProfileMapper.insert(record);
        }

        return record;
    }

    @Override
    @Transactional(rollbackFor = Exception.class)
    public int batchSaveProfiles(Integer shopId, List<DishFoodProfileInputDTO> inputs) {
        if (inputs == null || inputs.isEmpty()) {
            return 0;
        }
        int count = 0;
        for (DishFoodProfileInputDTO item : inputs) {
            if (item.getShop_id() == null) {
                item.setShop_id(shopId);
            }
            saveOrUpdateProfile(item);
            count++;
        }
        return count;
    }

    @Override
    @Transactional(rollbackFor = Exception.class)
    public int autoInitStoreProfiles(Integer shopId) {
        int targetShopId = (shopId != null && shopId > 0) ? shopId : 1;

        List<Dish> dishes = dishMapper.selectList(null);
        if (dishes == null || dishes.isEmpty()) {
            return 0;
        }

        List<DishFoodProfile> existingList = dishFoodProfileMapper.selectList(
                new QueryWrapper<DishFoodProfile>().eq("shop_id", targetShopId));
        Set<Integer> configuredDishIds = (existingList != null)
                ? existingList.stream().map(DishFoodProfile::getDish_id).collect(Collectors.toSet())
                : Collections.emptySet();

        int count = 0;
        for (Dish d : dishes) {
            if (configuredDishIds.contains(d.getId())) {
                continue;
            }

            String name = (d.getName() != null) ? d.getName() : "";
            DishFoodProfileInputDTO dto = new DishFoodProfileInputDTO();
            dto.setDish_id(d.getId());
            dto.setShop_id(targetShopId);
            dto.setNutrition_source("ESTIMATED");

            // 规则推断 1：后厨是否能做免辣
            if (name.contains("麻辣") || name.contains("变态辣") || name.contains("特辣") || name.contains("香辣")) {
                dto.setNon_spicy_available(0);
                dto.setSpice_options(Arrays.asList("中辣", "特辣"));
            } else {
                dto.setNon_spicy_available(1);
                dto.setSpice_options(Arrays.asList("不辣", "微辣", "中辣"));
            }

            // 规则推断 2：过敏原检测
            List<String> allergens = new ArrayList<>();
            if (name.contains("花生")) allergens.add("PEANUT");
            if (name.contains("虾") || name.contains("蟹") || name.contains("生蚝") || name.contains("扇贝") || name.contains("海鲜")) {
                allergens.add("SEAFOOD");
            }
            if (name.contains("冷面") || name.contains("炒饭") || name.contains("馒头") || name.contains("面包")) {
                allergens.add("GLUTEN");
            }
            dto.setVerified_allergens(allergens);

            // 规则推断 3：健身控重与热量预估
            if (name.contains("茶") || name.contains("水") || name.contains("黄瓜") || name.contains("茄子") || name.contains("蔬菜") || name.contains("菌")) {
                dto.setIs_suitable_fitness(1);
                dto.setCalories_kcal(BigDecimal.valueOf(80));
                dto.setProtein_g(BigDecimal.valueOf(3));
                dto.setFat_g(BigDecimal.valueOf(1));
            } else if (name.contains("串") || name.contains("肉") || name.contains("排骨") || name.contains("鸡")) {
                dto.setIs_suitable_fitness(name.contains("鸡胸") || name.contains("瘦牛") ? 1 : 0);
                dto.setCalories_kcal(BigDecimal.valueOf(260));
                dto.setProtein_g(BigDecimal.valueOf(22));
                dto.setFat_g(BigDecimal.valueOf(14));
            } else {
                dto.setIs_suitable_fitness(0);
                dto.setCalories_kcal(BigDecimal.valueOf(300));
            }

            saveOrUpdateProfile(dto);
            count++;
        }

        return count;
    }
}
