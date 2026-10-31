package com.lanf.controller;


import com.lanf.dto.CouponReceiveDTO;
import com.baomidou.mybatisplus.core.conditions.query.QueryWrapper;
import com.lanf.entity.ParkingPlate;
import com.lanf.entity.R;
import com.lanf.entity.User;
import com.lanf.service.IUserService;
import com.lanf.service.ParkingPlateService;
import com.lanf.interceptor.UserIdentityInterceptor;
import org.springframework.validation.annotation.Validated;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

import javax.annotation.Resource;
import javax.servlet.http.HttpServletRequest;
import java.util.Objects;


@RestController
@RequestMapping("/parking")
public class ParkingPlateController {

    @Resource
    private ParkingPlateService ParkingPlateService;
    @Resource
    private IUserService userService;

    /**
     * 领取停车优惠接口
     */
    @PostMapping("/receive")
    public R receiveCoupon(@Validated @RequestBody CouponReceiveDTO dto, HttpServletRequest request) {
        Long user_id = authenticatedUserId(request);
        String plate_number = dto.getPlate_number();
        if(user_id <= 0 || Objects.equals(plate_number, "")){
            return R.error("参数异常，请检查参数");
        }
        ParkingPlateService.getPlateByUserIdAndNumber(user_id,plate_number);
        return R.ok();
    }

    @GetMapping("/list")
    public R list(@RequestParam(required = false) String openid,
                  @RequestParam(required = false, name = "user_id") Long userId,
                  HttpServletRequest request) {
        Long uid = authenticatedUserId(request);
        if (uid == null || uid <= 0) {
            return R.error("缺少用户标识");
        }
        return R.ok().put("list", ParkingPlateService.list(new QueryWrapper<ParkingPlate>()
                .eq("user_id", uid)
                .orderByDesc("is_default")
                .orderByDesc("id")));
    }

    @PutMapping("/{id}/default")
    public R setDefault(@PathVariable Long id,
                        @RequestParam(required = false) String openid,
                        @RequestParam(required = false, name = "user_id") Long userId,
                        HttpServletRequest request) {
        Long uid = authenticatedUserId(request);
        if (uid == null || uid <= 0) {
            return R.error("缺少用户标识");
        }
        ParkingPlate target = ParkingPlateService.getById(id);
        if (target == null || !uid.equals(target.getUser_id())) {
            return R.error("车牌不存在");
        }
        ParkingPlate clear = new ParkingPlate();
        clear.setIs_default(0);
        ParkingPlateService.update(clear, new QueryWrapper<ParkingPlate>().eq("user_id", uid));
        target.setIs_default(1);
        ParkingPlateService.updateById(target);
        return R.ok();
    }

    @DeleteMapping("/{id}")
    public R delete(@PathVariable Long id,
                    @RequestParam(required = false) String openid,
                    @RequestParam(required = false, name = "user_id") Long userId,
                    HttpServletRequest request) {
        Long uid = authenticatedUserId(request);
        if (uid == null || uid <= 0) {
            return R.error("缺少用户标识");
        }
        ParkingPlate target = ParkingPlateService.getById(id);
        if (target == null || !uid.equals(target.getUser_id())) {
            return R.error("车牌不存在");
        }
        ParkingPlateService.removeById(id);
        return R.ok();
    }

    private Long authenticatedUserId(HttpServletRequest request) {
        Object openid = request.getAttribute(UserIdentityInterceptor.ATTR_USER_OPENID);
        if (openid != null) {
            User user = userService.getUserByOpenid(openid.toString());
            if (user != null && user.getId() != null) {
                return user.getId().longValue();
            }
        }
        return null;
    }
}
