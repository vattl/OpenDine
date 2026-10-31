package com.lanf.mapper;

import com.baomidou.mybatisplus.core.mapper.BaseMapper;
import com.lanf.entity.InviteRecord;
import org.apache.ibatis.annotations.Mapper;
import org.apache.ibatis.annotations.Param;
import org.apache.ibatis.annotations.Select;
import java.util.List;

@Mapper
public interface InviteRecordMapper extends BaseMapper<InviteRecord> {
    // 根据邀请者openid查询邀请记录
    List<InviteRecord> selectByInviterOpenid(String inviter_openid);

    // 根据邀请码查询
    InviteRecord selectByInviteCode(String invite_code,String invitee_openid);

    @Select("SELECT * FROM t_invite_record "
            + "WHERE first_order_no = #{orderNo} LIMIT 1 FOR UPDATE")
    InviteRecord selectByFirstOrderNoForUpdate(@Param("orderNo") String orderNo);

}
