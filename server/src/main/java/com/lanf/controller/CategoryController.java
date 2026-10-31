package com.lanf.controller;


import com.baomidou.mybatisplus.core.conditions.query.QueryWrapper;
import com.lanf.entity.Category;
import com.lanf.entity.R;
import com.lanf.service.ICategoryService;
import com.lanf.service.IShopService;
import com.lanf.service.ShopMenuSortService;
import com.lanf.util.ShopChainSupport;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

import javax.servlet.http.HttpServletRequest;
import java.util.HashMap;
import java.util.List;
import java.util.Map;


/**
 * 菜单分类控制器
 */
@RestController
@RequestMapping("/category")
public class CategoryController {

    /** C 端未传门店时默认总店，与 {@link DishController} 一致 */
    private static final int DEFAULT_C_SHOP_ID = 1;

    @Autowired
    private ICategoryService categoryService;

    @Autowired
    private IShopService shopService;

    @Autowired
    private ShopMenuSortService shopMenuSortService;

    /**
     * 查询所有菜单分类（C 端须携带门店上下文，与 {@link DishController#listAll} 一致）
     */
    @RequestMapping("/listAll")
    public R listAll(@RequestParam(name = "shop_id", required = false) Integer shopId,
                     @RequestParam(name = "shop_code", required = false) String shopCode,
                     HttpServletRequest request) {
        Integer resolved;
        try {
            resolved = ShopChainSupport.resolveShopChain(request, shopId,
                    shopCode != null ? shopCode.trim() : null,
                    shopService::requireActiveShopIdByCode);
        } catch (RuntimeException e) {
            return R.error(e.getMessage());
        }
        if (resolved == null) {
            resolved = DEFAULT_C_SHOP_ID;
        }
        List<Category> list = categoryService.list(new QueryWrapper<Category>()
                .orderByAsc("sorting").orderByAsc("id"));
        shopMenuSortService.orderCategories(resolved, list);
        Map<String, Object> map = new HashMap<>();
        map.put("categoryListAll", list);
        return R.ok(map);
    }

}
