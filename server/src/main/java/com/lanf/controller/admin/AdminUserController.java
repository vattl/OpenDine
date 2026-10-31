package com.lanf.controller.admin;

import com.lanf.entity.R;
import com.lanf.entity.User;
import com.lanf.security.AdminShopScopeGuard;
import com.lanf.service.IUserService;
import com.lanf.util.AdminShopRequest;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.format.annotation.DateTimeFormat;
import org.springframework.web.bind.annotation.*;

import javax.servlet.http.HttpServletRequest;
import java.util.Date;
import java.util.List;

/**
 * 运营后台 - 用户统计与按时间范围查询。
 * 按 t_user.time（注册时间）统计近 7 天、上月、本月、自定义时间段内的用户列表。
 * 支持门店隔离（shopId / X-Shop-Id）及总部全量模式（allShops=true）。
 */
@RestController
@RequestMapping("/admin/user")
public class AdminUserController {

    @Autowired
    private IUserService userService;
    @Autowired(required = false)
    private AdminShopScopeGuard adminShopScopeGuard;
    @Autowired
    private HttpServletRequest httpServletRequest;

    private Integer resolveTargetShopId(Integer requestedShopId, Boolean allShops, int[] outHolder, R[] errorHolder) {
        if (adminShopScopeGuard != null) {
            if (Boolean.TRUE.equals(allShops)) {
                R guardR = adminShopScopeGuard.requireHeadquarters();
                if (guardR != null) {
                    errorHolder[0] = guardR;
                    return null;
                }
                outHolder[0] = 0;
            } else {
                R guardR = adminShopScopeGuard.resolveTargetShopId(requestedShopId, outHolder);
                if (guardR != null) {
                    errorHolder[0] = guardR;
                    return null;
                }
            }
        }
        Integer shopId = outHolder[0] > 0 ? Integer.valueOf(outHolder[0]) : AdminShopRequest.getResolvedShopId(httpServletRequest);
        if (Boolean.TRUE.equals(allShops)) {
            shopId = 0;
        }
        return shopId;
    }

    public R sevenDays() {
        return sevenDays(null, null);
    }

    public R lastMonth() {
        return lastMonth(null, null);
    }

    public R thisMonth() {
        return thisMonth(null, null);
    }

    public R scopeGet(Date startTime, Date endTime) {
        return scopeGet(startTime, endTime, null, null);
    }

    /**
     * 查询近 7 天内注册的用户。
     */
    @GetMapping("/sevenDays")
    public R sevenDays(@RequestParam(required = false) Integer shopId,
                       @RequestParam(required = false) Boolean allShops) {
        int[] holder = new int[1];
        R[] err = new R[1];
        Integer targetShopId = resolveTargetShopId(shopId, allShops, holder, err);
        if (err[0] != null) {
            return err[0];
        }
        List<User> list = userService.getSevenDaysUser(targetShopId);
        return R.ok().put("list", list).put("total", list != null ? list.size() : 0);
    }

    /**
     * 查询上月注册的用户。
     */
    @GetMapping("/lastMonth")
    public R lastMonth(@RequestParam(required = false) Integer shopId,
                        @RequestParam(required = false) Boolean allShops) {
        int[] holder = new int[1];
        R[] err = new R[1];
        Integer targetShopId = resolveTargetShopId(shopId, allShops, holder, err);
        if (err[0] != null) {
            return err[0];
        }
        List<User> list = userService.getLastMonthUser(targetShopId);
        return R.ok().put("list", list).put("total", list != null ? list.size() : 0);
    }

    /**
     * 查询本月注册的用户。
     */
    @GetMapping("/thisMonth")
    public R thisMonth(@RequestParam(required = false) Integer shopId,
                        @RequestParam(required = false) Boolean allShops) {
        int[] holder = new int[1];
        R[] err = new R[1];
        Integer targetShopId = resolveTargetShopId(shopId, allShops, holder, err);
        if (err[0] != null) {
            return err[0];
        }
        List<User> list = userService.getThisMonthUser(targetShopId);
        return R.ok().put("list", list).put("total", list != null ? list.size() : 0);
    }

    /**
     * 查询指定时间段内注册的用户。
     */
    @GetMapping("/scope")
    public R scopeGet(
            @RequestParam(required = false) @DateTimeFormat(pattern = "yyyy-MM-dd HH:mm:ss") Date startTime,
            @RequestParam(required = false) @DateTimeFormat(pattern = "yyyy-MM-dd HH:mm:ss") Date endTime,
            @RequestParam(required = false) Integer shopId,
            @RequestParam(required = false) Boolean allShops) {
        if (startTime == null || endTime == null) {
            return R.error("startTime 与 endTime 不能为空");
        }
        if (startTime.after(endTime)) {
            return R.error("startTime 不能大于 endTime");
        }
        int[] holder = new int[1];
        R[] err = new R[1];
        Integer targetShopId = resolveTargetShopId(shopId, allShops, holder, err);
        if (err[0] != null) {
            return err[0];
        }
        List<User> list = userService.getScopeUser(startTime, endTime, targetShopId);
        return R.ok().put("list", list).put("total", list != null ? list.size() : 0);
    }

    @PostMapping("/scope")
    public R scopePost(@RequestBody(required = false) java.util.Map<String, Object> body) {
        if (body == null || body.get("startTime") == null || body.get("endTime") == null) {
            return R.error("请求体需包含 startTime、endTime");
        }
        Date startTime = parseDateTime(String.valueOf(body.get("startTime")));
        Date endTime = parseDateTime(String.valueOf(body.get("endTime")));
        if (startTime == null || endTime == null) {
            return R.error("startTime、endTime 格式错误，请使用 yyyy-MM-dd HH:mm:ss 或 yyyy-MM-dd");
        }
        if (startTime.after(endTime)) {
            return R.error("startTime 不能大于 endTime");
        }
        Integer requestedShopId = null;
        Object rawShop = body.get("shopId") != null ? body.get("shopId") : body.get("shop_id");
        if (rawShop instanceof Number) {
            requestedShopId = ((Number) rawShop).intValue();
        } else if (rawShop != null && !rawShop.toString().trim().isEmpty()) {
            try {
                requestedShopId = Integer.parseInt(rawShop.toString().trim());
            } catch (NumberFormatException ignored) {}
        }
        Boolean allShops = null;
        Object rawAll = body.get("allShops") != null ? body.get("allShops") : body.get("all_shops");
        if (rawAll instanceof Boolean) {
            allShops = (Boolean) rawAll;
        } else if (rawAll != null) {
            allShops = Boolean.parseBoolean(rawAll.toString().trim());
        }

        int[] holder = new int[1];
        R[] err = new R[1];
        Integer targetShopId = resolveTargetShopId(requestedShopId, allShops, holder, err);
        if (err[0] != null) {
            return err[0];
        }
        List<User> list = userService.getScopeUser(startTime, endTime, targetShopId);
        return R.ok().put("list", list).put("total", list != null ? list.size() : 0);
    }

    private static Date parseDateTime(String s) {
        if (s == null || s.trim().isEmpty()) return null;
        s = s.trim();
        try {
            if (s.length() > 10) {
                return new java.text.SimpleDateFormat("yyyy-MM-dd HH:mm:ss").parse(s);
            }
            return new java.text.SimpleDateFormat("yyyy-MM-dd").parse(s);
        } catch (Exception e) {
            return null;
        }
    }
}
