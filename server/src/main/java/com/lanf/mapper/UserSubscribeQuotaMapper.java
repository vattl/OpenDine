package com.lanf.mapper;

import com.baomidou.mybatisplus.core.mapper.BaseMapper;
import com.lanf.entity.UserSubscribeQuota;
import org.apache.ibatis.annotations.Mapper;
import org.apache.ibatis.annotations.Param;
import org.apache.ibatis.annotations.Update;

/**
 * 用户微信订阅消息可用额度与台账 Mapper
 */
@Mapper
public interface UserSubscribeQuotaMapper extends BaseMapper<UserSubscribeQuota> {

    /**
     * 用户同意授权：若存在则可用额度+1、accept_count+1，更新 last_authorized_at
     */
    @Update("INSERT INTO t_user_subscribe_quota " +
            "(openid, scene_code, template_id, available_quota, accept_count, reject_count, ban_status, last_authorized_at, created_at, updated_at) " +
            "VALUES (#{openid}, #{sceneCode}, #{templateId}, 1, 1, 0, 0, NOW(), NOW(), NOW()) " +
            "ON DUPLICATE KEY UPDATE " +
            "available_quota = available_quota + 1, " +
            "accept_count = accept_count + 1, " +
            "ban_status = 0, " +
            "last_authorized_at = NOW(), " +
            "updated_at = NOW()")
    int recordAccept(@Param("openid") String openid,
                     @Param("sceneCode") String sceneCode,
                     @Param("templateId") String templateId);

    /**
     * 用户拒绝授权：记录 reject_count+1，若 ban 则置 ban_status=1
     */
    @Update("INSERT INTO t_user_subscribe_quota " +
            "(openid, scene_code, template_id, available_quota, accept_count, reject_count, ban_status, created_at, updated_at) " +
            "VALUES (#{openid}, #{sceneCode}, #{templateId}, 0, 0, 1, #{banStatus}, NOW(), NOW()) " +
            "ON DUPLICATE KEY UPDATE " +
            "reject_count = reject_count + 1, " +
            "ban_status = CASE WHEN #{banStatus} = 1 THEN 1 ELSE ban_status END, " +
            "updated_at = NOW()")
    int recordReject(@Param("openid") String openid,
                     @Param("sceneCode") String sceneCode,
                     @Param("templateId") String templateId,
                     @Param("banStatus") int banStatus);

    /**
     * 消耗一次额度：扣减1并更新 last_sent_at
     */
    @Update("UPDATE t_user_subscribe_quota " +
            "SET available_quota = GREATEST(0, available_quota - 1), " +
            "last_sent_at = NOW(), " +
            "updated_at = NOW() " +
            "WHERE openid = #{openid} AND scene_code = #{sceneCode} AND available_quota > 0")
    int decrementQuota(@Param("openid") String openid,
                       @Param("sceneCode") String sceneCode);

    /**
     * 遇到 43101（额度不足或用户拒收）：校准配额归零
     */
    @Update("UPDATE t_user_subscribe_quota " +
            "SET available_quota = 0, " +
            "updated_at = NOW() " +
            "WHERE openid = #{openid} AND scene_code = #{sceneCode}")
    int resetQuotaToZero(@Param("openid") String openid,
                         @Param("sceneCode") String sceneCode);
}
