package com.lanf.controller.admin;

import com.lanf.audit.annotation.AuditLog;
import com.baomidou.mybatisplus.core.conditions.query.QueryWrapper;
import com.baomidou.mybatisplus.core.conditions.update.UpdateWrapper;
import com.lanf.entity.Category;
import com.lanf.entity.Dish;
import com.lanf.entity.DishShop;
import com.lanf.entity.PageBean;
import com.lanf.entity.R;
import com.lanf.entity.Table;
import com.lanf.mapper.DishShopMapper;
import com.lanf.service.DishMenuPushService;
import com.lanf.service.ICategoryService;
import com.lanf.service.IDishService;
import com.lanf.service.ShopMenuSortService;
import com.lanf.util.AdminShopRequest;
import com.lanf.util.DateUtil;
import com.lanf.util.DishSoldOutSync;
import org.apache.commons.io.FileUtils;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.util.StringUtils;
import org.springframework.web.bind.annotation.*;
import org.springframework.web.multipart.MultipartFile;

import javax.servlet.http.HttpServletRequest;
import java.io.File;
import java.io.IOException;
import java.math.BigDecimal;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.Paths;
import java.util.*;
import java.util.stream.Collectors;

/**
 * 菜品管理
 */
@RestController
@RequestMapping("/admin/dish")
public class AdminDishController {

    @Autowired
    private IDishService dishService;

    @Autowired
    private ICategoryService categoryService;
    @Autowired
    private DishMenuPushService dishMenuPushService;
    @Autowired
    private HttpServletRequest httpServletRequest;
    @Autowired
    private DishShopMapper dishShopMapper;
    @Autowired
    private ShopMenuSortService shopMenuSortService;

    @Value("${dishImgsFilePath}")
    private String dishImgsFilePath;

    

    @Value("${activateImgsFilePath}")
    private String activateImgsFilePath;
    // 允许的图片后缀（白名单，防止恶意文件上传）
    private static final String[] ALLOWED_SUFFIX = {".jpg", ".jpeg", ".png", ".gif", ".webp"};

    // 单个文件最大大小（5MB，可配置）
    private static final long MAX_FILE_SIZE = 5 * 1024 * 1024;
    private static final int DEFAULT_SERVING_DURATION_MINUTES = 10;
    private static final Logger log = LoggerFactory.getLogger(AdminDishController.class);

    private static int soldOutFromStock(Integer stock) {
        return stock != null && stock >= 0 && stock <= 0 ? 1 : 0;
    }

    private static int stockEnabledFromValue(Integer stock) {
        return stock != null && stock >= 0 ? 1 : 0;
    }

    /**
     * 统一门店菜品库存与售罄状态：明确售罄优先清零；明确库存则由库存决定可售状态。
     * 未传库存/售罄字段时保留现状，但会修正历史上的矛盾数据。
     */
    private static void normalizeAvailability(DishShop link, Integer requestedStock, Integer requestedSoldOut) {
        if (Integer.valueOf(1).equals(requestedSoldOut)) {
            link.setStock(0);
            link.setStock_enabled(1);
            link.setSold_out(1);
            return;
        }
        if (requestedStock != null) {
            link.setStock(requestedStock);
            link.setStock_enabled(stockEnabledFromValue(requestedStock));
            link.setSold_out(soldOutFromStock(requestedStock));
            return;
        }
        if (Integer.valueOf(1).equals(link.getSold_out())) {
            link.setStock(0);
            link.setStock_enabled(1);
            return;
        }
        link.setStock_enabled(stockEnabledFromValue(link.getStock()));
        link.setSold_out(soldOutFromStock(link.getStock()));
    }

    private DishShop getOrCreateDishShop(Integer shopId, Integer dishId, Integer stock, Integer soldOut) {
        DishShop link = dishShopMapper.selectOne(new com.baomidou.mybatisplus.core.conditions.query.QueryWrapper<DishShop>()
                .eq("shop_id", shopId)
                .eq("dish_id", dishId)
                .last("LIMIT 1"));
        if (link == null) {
            link = new DishShop();
            link.setShop_id(shopId);
            link.setDish_id(dishId);
            link.setStock(stock != null ? stock : -1);
            link.setStock_enabled(stockEnabledFromValue(link.getStock()));
            link.setSold_out(soldOut != null ? soldOut : soldOutFromStock(link.getStock()));
            normalizeAvailability(link, stock, soldOut);
            link.setOnsale_override(1);
            bindCategoryFromTemplate(link, dishId);
            dishShopMapper.insert(link);
        } else {
            // 显式绑定兜底：存量挂载行分类为空且总部分类有效时回填，保证菜单按分类展示不丢菜
            bindCategoryFromTemplate(link, dishId);
        }
        return link;
    }

    /**
     * 门店菜品分类显式绑定：type_id_override 为空且总部菜品分类有效（存在于 t_category）时，
     * 回填总部分类 id。新建挂载行与存量行统一生效；请求显式传 typeId 时由
     * {@link #applyShopTextOverrides} 覆盖，本方法不改变已绑定分类。
     */
    private void bindCategoryFromTemplate(DishShop link, Integer dishId) {
        if (link.getType_id_override() != null) {
            return;
        }
        Dish template = dishId != null ? dishService.getById(dishId) : null;
        Integer typeId = template == null ? null : template.getTypeId();
        if (typeId != null
                && categoryService.count(new QueryWrapper<Category>().eq("id", typeId)) > 0) {
            link.setType_id_override(typeId);
        }
    }

    /**
     * 门店上下文编辑：将请求 Dish 中非空的门店差异字段写入 t_dish_shop 覆盖列。
     * 约定（与 unitprice / onsale_override 的 NULL 回退语义一致）：
     * 仅覆盖值非 null / 非空时写入；未传字段保持现有覆盖，不做清除（清除入口留待后续）。
     * 对应迁移：docs/db_migration_dish_shop_full_overrides.sql
     */
    private static void applyShopTextOverrides(DishShop link, Dish dish) {
        if (link == null || dish == null) {
            return;
        }
        if (dish.getUnitprice() != null) {
            link.setUnitprice(BigDecimal.valueOf(dish.getUnitprice().doubleValue()));
        }
        if (StringUtils.hasText(dish.getSpecification())) {
            link.setSpecification_override(dish.getSpecification());
        }
        if (StringUtils.hasText(dish.getName())) {
            link.setName_override(dish.getName());
        }
        if (StringUtils.hasText(dish.getImage())) {
            link.setImage_override(dish.getImage());
        }
        if (StringUtils.hasText(dish.getUnit())) {
            link.setUnit_override(dish.getUnit());
        }
        if (dish.getTypeId() != null) {
            link.setType_id_override(dish.getTypeId());
        }
        if (dish.getSorting() != null) {
            link.setSorting_override(dish.getSorting());
        }
        if (dish.getServing_duration_minutes() != null) {
            link.setServing_duration_override(dish.getServing_duration_minutes());
        }
    }

    /**
     * 提取门店差异请求值（须在 save 将 Dish 置空以保护总部模板之前调用）。
     */
    private static Dish extractShopOverrideRequest(Dish dish) {
        Dish copy = new Dish();
        if (dish == null) {
            return copy;
        }
        copy.setUnitprice(dish.getUnitprice());
        copy.setName(dish.getName());
        copy.setImage(dish.getImage());
        copy.setUnit(dish.getUnit());
        copy.setSpecification(dish.getSpecification());
        copy.setTypeId(dish.getTypeId());
        copy.setSorting(dish.getSorting());
        copy.setServing_duration_minutes(dish.getServing_duration_minutes());
        return copy;
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
        Integer shopId = AdminShopRequest.getResolvedShopId(httpServletRequest);
        if (shopId != null) {
            map.put("shop_id", shopId);
        }
        List<Dish> list=dishService.list(map);
        Long total =dishService.getTotal(map);
        Map<String,Object> resultMap=new HashMap<>();
        resultMap.put("dishList",list);
        resultMap.put("total",total);
        return R.ok(resultMap);
    }

    /**
     * 总部标准菜分页（全量 t_dish，不按门店 t_dish_shop 过滤）。请求体与 {@link #list} 相同（PageBean），返回字段同为 dishList、total。
     */
    @PostMapping("/hqTemplateList")
    public R hqTemplateList(@RequestBody PageBean pageBean) {
        Map<String, Object> map = new HashMap<>();
        map.put("start", pageBean.getStart());
        map.put("pageSize", pageBean.getPageSize());
        if (pageBean.getQuery() != null && !pageBean.getQuery().trim().isEmpty()) {
            map.put("query", pageBean.getQuery().trim());
        }
        List<Dish> list = dishService.listHqTemplate(map);
        Long total = dishService.getTotalHqTemplate(map);
        Map<String, Object> resultMap = new HashMap<>();
        resultMap.put("dishList", list);
        resultMap.put("total", total);
        return R.ok(resultMap);
    }

    /**
     * 将总部菜品挂到当前门店菜单：写入 t_dish_shop（INSERT IGNORE 去重）。不复制 t_dish；分类沿用原 typeId。
     */
    @PostMapping("/importFromHq")
    @AuditLog(module = "dish", action = "admin_dish_import")
    public R importFromHq(@RequestBody Map<String, Object> body) {
        Integer shopId = AdminShopRequest.getResolvedShopId(httpServletRequest);
        if (shopId == null) {
            return R.error(4001, "缺少门店上下文，请传 X-Shop-Id 或 X-Shop-Code");
        }
        Object raw = body != null ? body.get("dishIds") : null;
        if (!(raw instanceof List)) {
            return R.error("dishIds 须为非空数组");
        }
        @SuppressWarnings("unchecked")
        List<Object> idObjs = (List<Object>) raw;
        if (idObjs.isEmpty()) {
            return R.error("dishIds 不能为空");
        }
        List<Integer> dishIds = new ArrayList<>();
        for (Object o : idObjs) {
            if (o == null) {
                continue;
            }
            if (o instanceof Number) {
                dishIds.add(((Number) o).intValue());
            } else {
                try {
                    dishIds.add(Integer.parseInt(o.toString().trim()));
                } catch (NumberFormatException e) {
                    return R.error("dishIds 元素须为整数");
                }
            }
        }
        if (dishIds.isEmpty()) {
            return R.error("dishIds 不能为空");
        }
        Map<String, Object> result = dishService.importFromHqToShop(shopId, dishIds);
        return R.ok(result);
    }

    /**
     * 新增或修改
     * 门店上下文（X-Shop-Id / X-Shop-Code）语义：
     * - 新增：先建总部模板（名称/价格/规格等写入 t_dish），再写入 t_dish_shop 库存/售罄/上下架；门店与总部一致（无覆盖）。
     * - 编辑：名称/价格/规格/图片/单位/分类/排序/出餐时长等门店差异字段仅写 t_dish_shop 覆盖列，不写 t_dish，避免跨店联动。
     * @param dish
     * @return
     */
    @PostMapping("/save")
    @AuditLog(module = "dish", action = "admin_dish_save", target = "#p0.id")
    public R save(@RequestBody Dish dish){
        if (dish == null) {
            return R.error("菜品参数不能为空");
        }
        boolean isUpdate = dish.getId() != null;
        if (!isUpdate && dish.getServing_duration_minutes() == null) {
            dish.setServing_duration_minutes(DEFAULT_SERVING_DURATION_MINUTES);
        }
        if (dish.getServing_duration_minutes() != null && dish.getServing_duration_minutes() <= 0) {
            return R.error("出餐时长必须为大于 0 的整数分钟");
        }
        dish.setTime(new Date());
        Integer shopId = AdminShopRequest.getResolvedShopId(httpServletRequest);
        Integer reqStock = dish.getStock();
        Integer reqSoldOut = dish.getSold_out();
        if (isUpdate) {
            Dish shopOverrideRequest = null;
            if (shopId != null) {
                Dish existing = dishService.getById(dish.getId());
                if (existing != null) {
                    dish.setOnsale(existing.isOnsale());
                }
                // 门店上下文：门店差异字段仅写 t_dish_shop，避免改到总部模板库存/价格/名称等影响所有门店
                shopOverrideRequest = extractShopOverrideRequest(dish);
                dish.setStock(null);
                dish.setSold_out(null);
                dish.setUnitprice(null);
                dish.setName(null);
                dish.setImage(null);
                dish.setUnit(null);
                dish.setSpecification(null);
                dish.setTypeId(null);
                dish.setSorting(null);
                dish.setServing_duration_minutes(null);
            }
            dishService.updateById(dish);
            if (shopId != null) {
                DishShop link = getOrCreateDishShop(shopId, dish.getId(), reqStock, reqSoldOut);
                normalizeAvailability(link, reqStock, reqSoldOut);
                if (link.getOnsale_override() == null) {
                    link.setOnsale_override(1);
                }
                applyShopTextOverrides(link, shopOverrideRequest);
                dishShopMapper.updateById(link);
            } else {
                // 无门店上下文（总部维护模板）时才允许改 t_dish.stock
                if (dish.getStock() == null) {
                    dishService.update(new UpdateWrapper<Dish>()
                            .set("stock", null)
                            .eq("id", dish.getId()));
                }
            }
        } else {
            dish.setOnsale(true);
            Integer targetDishId = null;
            Dish shopOverrideRequest = null;
            if (shopId != null) {
                dish.setStock(null);
                dish.setSold_out(0);
                shopOverrideRequest = extractShopOverrideRequest(dish);

                String trimmedName = dish.getName() != null ? dish.getName().trim() : "";
                if (StringUtils.hasText(trimmedName)) {
                    List<Dish> matches = dishService.list(new QueryWrapper<Dish>()
                            .apply("TRIM(name) = {0}", trimmedName)
                            .orderByAsc("id"));
                    if (matches != null && !matches.isEmpty()) {
                        Set<Integer> matchIds = matches.stream().map(Dish::getId).filter(Objects::nonNull).collect(Collectors.toSet());
                        List<DishShop> existingLinks = matchIds.isEmpty() ? Collections.emptyList() :
                                dishShopMapper.selectList(new QueryWrapper<DishShop>()
                                        .eq("shop_id", shopId)
                                        .in("dish_id", matchIds));
                        if (existingLinks != null && !existingLinks.isEmpty()) {
                            targetDishId = existingLinks.get(0).getDish_id();
                        } else {
                            targetDishId = matches.get(0).getId();
                        }
                    }
                }
            }
            if (dish.getSold_out() == null) {
                dish.setSold_out(0);
            }

            if (targetDishId != null) {
                // 命中总库已有菜品：复用该菜品 ID，不向 t_dish 插入重复行
                dish.setId(targetDishId);
                DishShop link = getOrCreateDishShop(shopId, targetDishId, reqStock, reqSoldOut);
                normalizeAvailability(link, reqStock, reqSoldOut);
                link.setOnsale_override(1); // 强制上架（恢复或新挂载）
                applyShopTextOverrides(link, shopOverrideRequest); // 写入门店覆盖信息
                dishShopMapper.updateById(link);
            } else {
                dishService.save(dish);
                if (shopId != null) {
                    DishShop link = getOrCreateDishShop(shopId, dish.getId(), reqStock, reqSoldOut);
                    normalizeAvailability(link, reqStock, reqSoldOut);
                    link.setOnsale_override(1);
                    dishShopMapper.updateById(link);
                }
            }
        }
        Dish latest = dish.getId() != null ? dishService.getById(dish.getId()) : null;
        if (latest != null) {
            if (shopId == null) {
                DishSoldOutSync.applyFromStock(latest);
                dishService.updateById(latest);
            }
            dishMenuPushService.notifyCatalogChanged(isUpdate ? "save_update" : "save_new",
                    latest.getId(), latest.getName(), latest.isOnsale());
        }
        return R.ok();
    }

    /**
     * 删除
     * @param id
     * @return
     */
    @GetMapping("/delete")
    public R delete(Integer id){
        Dish before = id != null ? dishService.getById(id) : null;
        if (id != null) {
            dishService.removeById(id);
            dishMenuPushService.notifyCatalogChanged("delete", id,
                    before != null ? before.getName() : null, null);
        }
        return R.ok();
    }

    /**
     * 更新上架 下架 状态
     * @return
     */
    @PostMapping("/updateOnSale")
    @AuditLog(module = "dish", action = "admin_dish_onsale", target = "#p0.id")
    public R updateOnSale(@RequestBody Dish dish){
        Dish d = dishService.getById(dish.getId());
        if (d == null) {
            return R.error("菜品不存在");
        }
        Integer shopId = AdminShopRequest.getResolvedShopId(httpServletRequest);
        if (shopId != null) {
            DishShop link = getOrCreateDishShop(shopId, d.getId(), -1, 0);
            link.setOnsale_override(dish.isOnsale() ? 1 : 0);
            if (dish.isOnsale()) {
                link.setSold_out(soldOutFromStock(link.getStock()));
            }
            dishShopMapper.updateById(link);
        } else {
            d.setOnsale(dish.isOnsale());
            if (dish.isOnsale()) {
                DishSoldOutSync.applyFromStock(d);
            }
            dishService.updateById(d);
        }
        dishMenuPushService.notifyCatalogChanged("updateOnSale", d.getId(), d.getName(), dish.isOnsale());
        return R.ok();
    }

    /**
     * 更新可售状态（售罄标记）：售罄时同步将库存清零，不改 {@code onsale}。
     */
    @PostMapping("/updateSaleStatus")
    @AuditLog(module = "dish", action = "admin_dish_sale_status", target = "#p0.id")
    public R updateSaleStatus(@RequestBody Dish body) {
        if (body == null || body.getId() == null || body.getSold_out() == null) {
            return R.error("id 与 sold_out 不能为空");
        }
        int so = body.getSold_out();
        if (so != 0 && so != 1) {
            return R.error("sold_out 仅允许 0（可售）或 1（已售罄）");
        }
        Dish d = dishService.getById(body.getId());
        if (d == null) {
            return R.error("菜品不存在");
        }
        Integer shopId = AdminShopRequest.getResolvedShopId(httpServletRequest);
        if (shopId == null) {
            return R.error(4001, "缺少门店上下文，请传 X-Shop-Id 或 X-Shop-Code");
        }
        DishShop link = getOrCreateDishShop(shopId, d.getId(), -1, so);
        normalizeAvailability(link, null, so);
        if (so == 0 && Integer.valueOf(1).equals(link.getSold_out())) {
            return R.error("库存为 0，请先补充库存后恢复可售");
        }
        dishShopMapper.updateById(link);
        dishMenuPushService.notifyCatalogChanged("updateSaleStatus", d.getId(), d.getName(), d.isOnsale());
        return R.ok();
    }

    /**
     * 拖拽更新菜品排序
     * targetIndex 为当前门店、菜品生效分类内的 1-based 位置。
     * 只更新当前门店 t_dish_shop.sorting_override，不写 t_dish.sorting。
     */
    @PostMapping("/sort")
    @AuditLog(module = "dish", action = "admin_dish_sort")
    public R sort(@RequestBody Map<String, Integer> body) {
        if (body == null) {
            return R.error("参数不能为空");
        }
        Integer id = body.get("id");
        Integer targetIndex = body.get("targetIndex"); // 前端传：拖拽位置的 sorting
        if (id == null || targetIndex == null) {
            return R.error("参数缺失：id 或 targetIndex（拖拽位置 sorting ）");
        }
        Integer shopId = AdminShopRequest.getResolvedShopId(httpServletRequest);
        try {
            Dish dish = shopMenuSortService.sortDishes(shopId, id, targetIndex);
            dishMenuPushService.notifyCatalogChanged("sort", id, dish.getName(), null);
            return R.ok();
        } catch (ShopMenuSortService.MenuSortException e) {
            return R.error(e.getCode(), e.getMessage());
        }
    }

    /**
     * 上传菜品图片
     * @param file
     * @return
     * @throws Exception
     */
    @PostMapping("/uploadImage") // 明确请求方式为POST（原@RequestMapping支持所有方式，不安全）
    public Map<String, Object> uploadImage(MultipartFile file, HttpServletRequest request) {
        // 统一返回结果结构
        Map<String, Object> result = new HashMap<>(4);
        result.put("code", 1); // 默认失败状态码
        result.put("msg", "上传失败");
        String type = request.getParameter("type");
        // 1. 校验文件是否为空
        if (file == null || file.isEmpty()) {
            result.put("msg", "请选择要上传的图片");
            return result;
        }

        try {
            // 2. 校验文件大小
            if (file.getSize() > MAX_FILE_SIZE) {
                result.put("msg", "图片大小不能超过5MB");
                return result;
            }

            // 3. 校验文件后缀（忽略大小写）
            String fileName = file.getOriginalFilename();
            if (fileName == null || !fileName.contains(".")) {
                result.put("msg", "文件名格式错误");
                return result;
            }
            String suffixName = fileName.substring(fileName.lastIndexOf(".")).toLowerCase();
            boolean isAllowed = false;
            for (String allowSuffix : ALLOWED_SUFFIX) {
                if (allowSuffix.equals(suffixName)) {
                    isAllowed = true;
                    break;
                }
            }
            if (!isAllowed) {
                result.put("msg", "仅支持" + String.join(",", ALLOWED_SUFFIX) + "格式的图片");
                return result;
            }

            // 4. 生成唯一文件名（UUID避免冲突，比时间戳更可靠）
            String newFileName = UUID.randomUUID().toString().replace("-", "") + suffixName;

            // 5. 确保存储目录存在（避免目录不存在导致IO异常）
            Path uploadPath = null;
            String imageAccessPrefix = null;
            if(Objects.equals(type, "advertising")){
                uploadPath = Paths.get(activateImgsFilePath);
                imageAccessPrefix = "/image/advertising/";
            }else{
                uploadPath = Paths.get(dishImgsFilePath);
                imageAccessPrefix = "/image/dish/";
            }

            if (!Files.exists(uploadPath)) {
                Files.createDirectories(uploadPath);
            }

            // 6. 写入文件（使用Java NIO，比FileUtils更高效，且自动关闭流）
            Path targetPath = uploadPath.resolve(newFileName);
            Files.copy(file.getInputStream(), targetPath);

            // 7. 构建返回结果（访问路径支持配置化）
            Map<String, Object> data = new HashMap<>(2);
            data.put("imageName", newFileName);

            data.put("src", imageAccessPrefix + newFileName);

            result.put("code", 0);
            result.put("msg", "上传成功");
            result.put("data", data);

        } catch (IOException e) {
            // 日志记录（实际项目中使用SLF4J+Logback）

            log.error("图片上传失败：",e);
            result.put("msg", "图片上传失败：" + e.getMessage());
        } catch (Exception e) {
            // 捕获其他异常（如权限不足等）
            log.error("系统异常，请联系管理员",e);
            result.put("msg", "系统异常，请联系管理员");
        }

        return result;
    }

}
