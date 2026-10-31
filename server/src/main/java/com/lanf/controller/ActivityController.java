package com.lanf.controller;

import com.lanf.dto.PopupDTO;
import com.lanf.entity.ActivityPopup;
import com.lanf.entity.Banner;
import com.lanf.entity.R;
import com.lanf.entity.User;
import com.lanf.notify.service.UnifiedNotificationService;
import com.lanf.service.IActivityPopupService;
import com.lanf.service.IShopService;
import com.lanf.service.IUserService;
import com.lanf.util.ActivityPopupShopFilter;
import com.lanf.util.ShopChainSupport;
import lombok.RequiredArgsConstructor;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.util.StringUtils;
import org.springframework.web.bind.annotation.*;

import javax.servlet.http.HttpServletRequest;
import java.util.*;

/**
 * 活动相关接口控制器
 */
@RestController
@RequestMapping("/activity")
@RequiredArgsConstructor
public class ActivityController {

    private static final int DEFAULT_C_SHOP_ID = 1;

    private static final Logger log = LoggerFactory.getLogger(ActivityController.class);

    private final IActivityPopupService activityPopupService;
    private final IUserService userService;
    private final IShopService shopService;

    @Autowired(required = false)
    private UnifiedNotificationService unifiedNotificationService;


    /**
     * 获取点餐页面的活动弹窗
     * @return 活动弹窗数据
     */
    @PostMapping("/popup")
    public R getDiningPopup(@RequestBody User us, String type,
                            @RequestParam(name = "shop_id", required = false) Integer shopId,
                            @RequestParam(name = "shop_code", required = false) String shopCode,
                            HttpServletRequest request) {
        try {
            User user = null;

            if(us != null && StringUtils.hasText(us.getOpenid())){
                user = userService.getUserByOpenid(us.getOpenid());
            }
            if(type == null || type.isEmpty()){
                return R.error("类型错误");
            }
            int userType;
            if(user == null ) {
                userType = 0;
            }else{
                userType = user.getUser_type();
            }

            Integer resolvedShop = resolveShopId(request, shopId, shopCode);
            ActivityPopup validPopup = activityPopupService.getValidDiningPopup(1, userType, type, resolvedShop);


            // 构建返回结果
            Map<String, Object> result = new HashMap<>();
            result.put("hasActivity", validPopup != null);
            result.put("activity", validPopup);

            return R.ok(result);
        } catch (Exception e) {
            log.error("获取活动弹窗失败，请求参数：{}", us, e);
            return R.error("获取活动失败，请重试");
        }
    }

    /**
     * 获取点餐页面的活动弹窗
     * @return 活动弹窗数据
     */
    @PostMapping("/popupList")
    public R getDiningPopupList(@RequestBody PopupDTO PO, HttpServletRequest request) {
        try {
            User user = null;
            String type = PO != null ? PO.getType() : null;
            if (PO != null && StringUtils.hasText(PO.getOpenid())) {
                user = userService.getUserByOpenid(PO.getOpenid());
            }
            if(type == null || type.isEmpty()){
                type = "page_activity";
            }
            int userType;
            if(user == null ) {
                userType = 0;
            }else{
                userType = user.getUser_type();
            }

            Integer resolvedShop = resolveShopId(request,
                    PO != null ? PO.getShop_id() : null,
                    PO != null ? PO.getShop_code() : null);
            List<ActivityPopup> validPopup = activityPopupService.getValidDiningPopupList(1, userType, type, resolvedShop);


            // 构建返回结果
            Map<String, Object> result = new HashMap<>();
            result.put("hasActivity", validPopup != null);
            result.put("activity", validPopup);

            return R.ok(result);
        } catch (Exception e) {
            log.error("获取活动弹窗失败，请求参数：{}", PO, e);
            return R.error("获取活动失败，请重试");
        }
    }
    @PostMapping("/updatePopup")
    public R updatePopup(@RequestBody ActivityPopup pop) {
        try{
            ActivityPopup popup = activityPopupService.getById(pop.getId());
            if(popup == null){
                return R.error("弹窗不存在");
            }
            if (pop.getApply_shop_ids() != null) {
                pop.setApply_shop_ids(ActivityPopupShopFilter.normalizeForSave(pop.getApply_shop_ids()));
            }
            boolean updata =  activityPopupService.updateById(pop);
            if(updata){
                if (unifiedNotificationService != null) {
                    try {
                        unifiedNotificationService.publishActivityPopupChanged("UPDATED", pop);
                    } catch (Exception ignore) {
                    }
                }
                return R.ok("更新成功");
            }else{
                return R.error("更新失败");
            }


        }catch (Exception e){
            return R.error("服务器异常："+e.getMessage());
        }

    }
    @PostMapping("/addPopup")
    public R addPopup(@RequestBody ActivityPopup pop) {
        try {
            // 1. 非空校验（修复逻辑判断错误）
            if (pop == null) {
                log.warn("新增活动弹窗失败：传入参数为空");
                return R.error("添加失败，参数不能为空！");
            }
            // 正确逻辑：名称为空 或 图片路径为空 → 返回失败（trim() 处理空格）
            if ("".equals(pop.getName().trim()) || "".equals(pop.getPopup_image().trim())) {
                log.warn("新增活动弹窗失败：必填字段为空，参数：{}", pop);
                return R.error("添加失败，弹窗名称和图片路径不能为空！");
            }
            // 2. 时间字段校验（避免无效时间）
            if (pop.getStart_time() == null || pop.getEnd_time() == null) {
                log.warn("新增活动弹窗失败：时间字段为空，参数：{}", pop);
                return R.error("添加失败，开始时间和结束时间不能为空！");
            }
            if (pop.getEnd_time().before(pop.getStart_time())) {
                log.warn("新增活动弹窗失败：结束时间早于开始时间，参数：{}", pop);
                return R.error("添加失败，结束时间必须晚于开始时间！");
            }
            // 3. 其他字段默认值补充（避免 null 入库）
            if (pop.getIs_enabled() == null) {
                pop.setIs_enabled(1); // 默认启用
            }
            if (pop.getMax_show_count() == null) {
                pop.setMax_show_count(0); // 默认最大展示次数 0
            }
            if (pop.getSorting() == null) {
                pop.setSorting(0); // 默认排序值 0
            }
            pop.setApply_shop_ids(ActivityPopupShopFilter.normalizeForSave(pop.getApply_shop_ids()));
            // 4. 调用服务层保存
            boolean saveSuccess = activityPopupService.save(pop);
            if (saveSuccess) {
                log.info("新增活动弹窗成功，弹窗名称：{}，ID：{}", pop.getName(), pop.getId());
                if (unifiedNotificationService != null) {
                    try {
                        unifiedNotificationService.publishActivityPopupChanged("ADDED", pop);
                    } catch (Exception ignore) {
                    }
                }
                return R.ok("添加成功");
            } else {
                log.error("新增活动弹窗失败：服务层保存返回false，参数：{}", pop);
                return R.error("添加失败，服务层保存失败！");
            }
        } catch (Exception e) {
            // 记录完整异常堆栈（便于排查）
            log.error("新增活动弹窗异常，参数：{}", pop, e);
            return R.error("添加失败，服务器异常：" + e.getMessage());
        }
    }



    @PostMapping("/getCarouselDetail")
    public R getCarouselDetail(@RequestBody ActivityPopup pop) {
        if(pop.getId() == null){return R.error("获取失败，ID不能为空！");}
        ActivityPopup Popup = activityPopupService.getById(pop.getId());
        return R.ok().put("popup", Popup);

    }

    @GetMapping ("/getAllPopup")
    public R getAllPopup() {

        List<ActivityPopup> Popup = activityPopupService.getAllPopup();
        return R.ok().put("popup", Popup);

    }
    @PostMapping("/deletePopup")
    public R deletePopup(@RequestBody ActivityPopup pop) {
        try {
            if (pop == null || pop.getId() == null) {
                return R.error("ID不能为空");
            }
            boolean removeSuccess = activityPopupService.removeById(pop.getId());
            if (removeSuccess) {
                if (unifiedNotificationService != null) {
                    try {
                        unifiedNotificationService.publishActivityPopupChanged("DELETED", pop);
                    } catch (Exception ignore) {
                    }
                }
                return R.ok();
            }else{
                return R.error("删除失败");
            }
        }catch (Exception e){
            log.error("服务器异常：{}", String.valueOf(e));
            return R.error("服务器异常："+e.getMessage());
        }
    }

    private Integer resolveShopId(HttpServletRequest request, Integer bodyShopId, String bodyShopCode) {
        try {
            Integer resolved = ShopChainSupport.resolveShopChain(request, bodyShopId,
                    bodyShopCode != null ? bodyShopCode.trim() : null,
                    shopService::requireActiveShopIdByCode);
            return resolved != null ? resolved : DEFAULT_C_SHOP_ID;
        } catch (RuntimeException e) {
            throw e;
        }
    }
}
