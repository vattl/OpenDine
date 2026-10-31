package com.lanf.service;

import com.lanf.entity.DishMaterialBom;

import java.util.List;

public interface IDishMaterialBomService {

    List<DishMaterialBom> listByShop(Integer shopId);

    void saveOrUpdate(DishMaterialBom bom);

    void deleteById(Long id, Integer requestShopId);
}
