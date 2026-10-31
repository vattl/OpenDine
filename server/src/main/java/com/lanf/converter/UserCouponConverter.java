package com.lanf.converter;

import com.lanf.dto.UserCouponDTO;
import com.lanf.entity.UserCoupon;
import org.mapstruct.Mapper;
import org.mapstruct.Mapping;
import org.mapstruct.Mappings;

import java.util.List;

// componentModel = "spring"：交给 Spring 管理，可通过 @Autowired 注入
@Mapper(componentModel = "spring")
public interface UserCouponConverter {

    /**
     * 单个实体 → 单个DTO（字段名一致时自动映射，不一致时用 @Mapping 手动映射）
     */
    @Mappings({
            // 示例：若实体字段名与DTO不一致（如实体 userOpenid → DTO openid），需手动映射
            // @Mapping(source = "userOpenid", target = "openid")
            // 字段名一致（如 id、status、expireTime）无需配置，自动映射
    })
    UserCouponDTO entityToResponseDto(UserCoupon userCoupon);

    /**
     * 实体列表 → DTO列表（MapStruct 自动批量转换，无需循环）
     */
    List<UserCouponDTO> entityListToResponseDtoList(List<UserCoupon> userCouponList);
}