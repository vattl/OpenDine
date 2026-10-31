package com.lanf.mapper;

import com.baomidou.mybatisplus.core.mapper.BaseMapper;
import com.lanf.entity.AccessApprovalRateLimit;
import org.apache.ibatis.annotations.Delete;
import org.apache.ibatis.annotations.Insert;
import org.apache.ibatis.annotations.Mapper;
import org.apache.ibatis.annotations.Param;
import org.apache.ibatis.annotations.Select;
import org.apache.ibatis.annotations.Update;

import java.util.Date;

@Mapper
public interface AccessApprovalRateLimitMapper extends BaseMapper<AccessApprovalRateLimit> {

    @Insert("INSERT IGNORE INTO t_access_approval_rate_limit "
            + "(limit_key, limit_scope, window_started_at, attempts, updated_at) "
            + "VALUES (#{limitKey}, #{limitScope}, #{now}, 0, #{now})")
    int insertIfAbsent(@Param("limitKey") String limitKey,
                       @Param("limitScope") String limitScope,
                       @Param("now") Date now);

    @Select("SELECT limit_key, limit_scope, window_started_at, attempts, blocked_until, updated_at "
            + "FROM t_access_approval_rate_limit WHERE limit_key = #{limitKey} FOR UPDATE")
    AccessApprovalRateLimit selectForUpdate(@Param("limitKey") String limitKey);

    @Update("UPDATE t_access_approval_rate_limit SET window_started_at = #{windowStartedAt}, "
            + "attempts = #{attempts}, blocked_until = #{blockedUntil}, updated_at = NOW(3) "
            + "WHERE limit_key = #{limitKey}")
    int updateState(@Param("limitKey") String limitKey,
                    @Param("windowStartedAt") Date windowStartedAt,
                    @Param("attempts") int attempts,
                    @Param("blockedUntil") Date blockedUntil);

    @Delete("DELETE FROM t_access_approval_rate_limit WHERE limit_key = #{limitKey}")
    int deleteByLimitKey(@Param("limitKey") String limitKey);
}
