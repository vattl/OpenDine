package com.lanf.mapper;

import com.baomidou.mybatisplus.core.mapper.BaseMapper;
import com.lanf.entity.OrderClientRequest;
import org.apache.ibatis.annotations.Delete;
import org.apache.ibatis.annotations.Insert;
import org.apache.ibatis.annotations.Param;
import org.apache.ibatis.annotations.Select;
import org.apache.ibatis.annotations.Update;

import java.util.Date;

public interface OrderClientRequestMapper extends BaseMapper<OrderClientRequest> {

    @Delete("DELETE FROM t_order_client_request WHERE shop_id=#{shopId} "
            + "AND client_request_id=#{requestId} AND expires_at<=NOW()")
    int deleteExpiredKey(@Param("shopId") Integer shopId, @Param("requestId") String requestId);

    @Insert("INSERT IGNORE INTO t_order_client_request(shop_id,admin_id,client_request_id,request_path,request_fingerprint,status,expires_at) "
            + "VALUES(#{shopId},#{adminId},#{requestId},#{requestPath},#{fingerprint},'PROCESSING',#{expiresAt})")
    int insertProcessing(@Param("shopId") Integer shopId, @Param("adminId") Integer adminId,
                         @Param("requestId") String requestId, @Param("requestPath") String requestPath,
                         @Param("fingerprint") String fingerprint,
                         @Param("expiresAt") Date expiresAt);

    @Select("SELECT * FROM t_order_client_request WHERE shop_id=#{shopId} "
            + "AND client_request_id=#{requestId} LIMIT 1 FOR UPDATE")
    OrderClientRequest lockByKey(@Param("shopId") Integer shopId, @Param("requestId") String requestId);

    @Update("UPDATE t_order_client_request SET status='COMPLETED',response_snapshot=#{snapshot},updated_at=NOW() "
            + "WHERE id=#{id} AND status='PROCESSING'")
    int complete(@Param("id") Long id, @Param("snapshot") String snapshot);
}
