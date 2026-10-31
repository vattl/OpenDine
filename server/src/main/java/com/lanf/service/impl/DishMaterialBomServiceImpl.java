package com.lanf.service.impl;

import com.baomidou.mybatisplus.core.conditions.query.QueryWrapper;
import com.lanf.entity.DishMaterialBom;
import com.lanf.mapper.DishMaterialBomMapper;
import com.lanf.service.IDishMaterialBomService;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Service;

import java.util.List;

@Service
public class DishMaterialBomServiceImpl implements IDishMaterialBomService {

    @Autowired
    private DishMaterialBomMapper dishMaterialBomMapper;

    @Override
    public List<DishMaterialBom> listByShop(Integer shopId) {
        if (shopId == null) {
            return java.util.Collections.emptyList();
        }
        return dishMaterialBomMapper.selectList(new QueryWrapper<DishMaterialBom>()
                .eq("shop_id", shopId)
                .orderByAsc("dish_id", "material_id"));
    }

    @Override
    public void saveOrUpdate(DishMaterialBom bom) {
        if (bom == null || bom.getShop_id() == null) {
            throw new RuntimeException("shop_id 不能为空");
        }
        if (bom.getId() != null) {
            dishMaterialBomMapper.updateById(bom);
        } else {
            dishMaterialBomMapper.insert(bom);
        }
    }

    @Override
    public void deleteById(Long id, Integer requestShopId) {
        if (id == null) {
            throw new RuntimeException("id 不能为空");
        }
        DishMaterialBom row = dishMaterialBomMapper.selectById(id);
        if (row == null) {
            throw new RuntimeException("BOM 不存在");
        }
        if (requestShopId != null && row.getShop_id() != null && !row.getShop_id().equals(requestShopId)) {
            throw new RuntimeException("无权删除其它门店的 BOM");
        }
        dishMaterialBomMapper.deleteById(id);
    }
}
