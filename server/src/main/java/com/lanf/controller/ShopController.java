package com.lanf.controller;

import com.baomidou.mybatisplus.core.conditions.query.QueryWrapper;
import com.lanf.entity.R;
import com.lanf.entity.Shop;
import com.lanf.service.IShopService;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import java.util.List;

/**
 * 小程序 C 端门店列表（公开，无需 B 端 JWT），与 docs/openapi.yaml 中 GET /shop/list 对齐。
 */
@RestController
@RequestMapping("/shop")
public class ShopController {

    @Autowired
    private IShopService shopService;

    /**
     * 仅返回营业中门店（status=1），按 id 升序。若库表已含 sort_order 列，可改为按 sort_order、id 排序。
     */
    @GetMapping("/list")
    public R list() {
        List<Shop> list = shopService.list(
                new QueryWrapper<Shop>()
                        .eq("status", 1)
                        .orderByAsc("id"));
        return R.ok().put("list", list);
    }
}
