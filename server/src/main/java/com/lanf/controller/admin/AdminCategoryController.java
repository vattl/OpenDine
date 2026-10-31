package com.lanf.controller.admin;

import com.lanf.audit.annotation.AuditLog;
import com.baomidou.mybatisplus.core.conditions.query.QueryWrapper;
import com.lanf.entity.*;
import com.lanf.service.ShopMenuSortService;
import com.lanf.service.ICategoryService;
import com.lanf.service.IDishService;
import com.lanf.util.AdminShopRequest;
import com.lanf.util.DateUtil;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.web.bind.annotation.*;

import javax.servlet.http.HttpServletRequest;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

/**
 * 菜单类别管理
 */
@RestController
@RequestMapping("/admin/category")
public class AdminCategoryController {

    @Autowired
    private ICategoryService categoryService;

    @Autowired
    private IDishService dishService;

    @Autowired
    private com.lanf.mapper.DishShopMapper dishShopMapper;

    @Autowired
    private HttpServletRequest httpServletRequest;

    @Autowired
    private ShopMenuSortService shopMenuSortService;

    /**
     * 查询所有菜品类别（全局类目主数据，供后台与收银台管理维护及菜单分类展示）。
     */
    @RequestMapping("/listAll")
    public R listAll(){
        QueryWrapper<Category> qw = new QueryWrapper<Category>();
        qw.orderByAsc("sorting").orderByAsc("id");
        List<Category> list = categoryService.list(qw);
        shopMenuSortService.orderCategories(AdminShopRequest.getResolvedShopId(httpServletRequest), list);
        Map<String,Object> resultMap=new HashMap<>();
        resultMap.put("categoryList",list);
        return R.ok(resultMap);
    }

    /**
     * 分页显示
     * @param pageBean
     * @return
     */
    @RequestMapping("/list")
    public R list(@RequestBody PageBean pageBean){
        System.out.println(pageBean);
        Map<String,Object> map=new HashMap<>();
        map.put("start",pageBean.getStart());
        map.put("pageSize",pageBean.getPageSize());
        List<Table> list=categoryService.list(map);
        Long total =categoryService.getTotal(map);
        Map<String,Object> resultMap=new HashMap<>();
        resultMap.put("categoryList",list);
        resultMap.put("total",total);
        return R.ok(resultMap);
    }

    /**
     * 添加
     * @param category
     * @return
     */
    @PostMapping("/add")
    @AuditLog(module = "category", action = "admin_category_add", target = "#p0.id")
    public R add(@RequestBody Category category){
        category.setValue(category.getLabel());
        category.setCid("a"+DateUtil.getCurrentDateStr());
        category.setCount(0);
        category.setSele_quantity(0);
        categoryService.save(category);
        return R.ok();
    }

    /**
     * 编辑更新类目（须传 id；改名称时 label 与 value 保持一致，与新增逻辑一致）
     */
    @PostMapping("/update")
    @AuditLog(module = "category", action = "admin_category_update", target = "#p0.id")
    public R update(@RequestBody Category category) {
        if (category == null || category.getId() == null) {
            return R.error("缺少类目 id");
        }
        Category existing = categoryService.getById(category.getId());
        if (existing == null) {
            return R.error("类目不存在");
        }
        if (category.getLabel() == null || category.getLabel().trim().isEmpty()) {
            return R.error("类目名称不能为空");
        }
        existing.setLabel(category.getLabel().trim());
        existing.setValue(category.getLabel().trim());
        if (category.getSorting() != null) {
            existing.setSorting(category.getSorting());
        }
        categoryService.updateById(existing);
        return R.ok();
    }

    /**
     * 删除
     * @param id
     * @return
     */
    @GetMapping("/delete")
    public R delete(Integer id){
        if(dishService.list(new QueryWrapper<Dish>().eq("typeId",id)).size()>0){
            return R.error("该菜品类目下有菜品，不能删除！");
        }
        // 门店覆盖分类（t_dish_shop.type_id_override）同样阻止删除，避免门店菜单丢失
        if(dishShopMapper.selectCount(new QueryWrapper<com.lanf.entity.DishShop>()
                .eq("type_id_override", id)) > 0){
            return R.error("该菜品类目下有门店菜品引用，不能删除！");
        }
        categoryService.removeById(id);
        return R.ok();
    }

    /**
     * 当前门店分类排名重排；targetIndex 为当前门店分类列表中的 1-based 位置。
     */
    @PostMapping("/sort")
    @AuditLog(module = "category", action = "admin_category_sort")
    public R sort(@RequestBody Map<String, Integer> body) {
        if (body == null) {
            return R.error("参数不能为空");
        }
        Integer id = body.get("id");
        Integer targetIndex = body.get("targetIndex"); // 前端传：拖拽后的目标位置（1-based 显示位置）
        if (id == null || targetIndex == null) {
            return R.error("参数缺失：id 或 targetIndex（拖拽目标位置）");
        }

        Integer shopId = AdminShopRequest.getResolvedShopId(httpServletRequest);
        try {
            shopMenuSortService.sortCategories(shopId, id, targetIndex);
            return R.ok();
        } catch (ShopMenuSortService.MenuSortException e) {
            return R.error(e.getCode(), e.getMessage());
        }
    }

}
