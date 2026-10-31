package com.lanf.mapper;

import com.lanf.entity.Order;
import com.lanf.entity.Table;
import org.apache.ibatis.annotations.Insert;
import org.apache.ibatis.annotations.Options;
import org.apache.ibatis.annotations.Param;
import org.apache.ibatis.annotations.Select;
import org.apache.ibatis.annotations.Update;

import java.util.Date;
import java.util.List;

public interface CashierTableOperationMapper {

    @Select("SELECT * FROM t_table WHERE shop_id=#{shopId} AND number=#{number} LIMIT 1 FOR UPDATE")
    Table lockTable(@Param("shopId") Integer shopId, @Param("number") String number);

    @Select("SELECT * FROM t_table WHERE shop_id=#{shopId} AND number IN (#{first},#{second}) " +
            "ORDER BY number,id FOR UPDATE")
    List<Table> lockTables(@Param("shopId") Integer shopId,
                           @Param("first") String first,
                           @Param("second") String second);

    @Select("SELECT * FROM t_order WHERE shop_id=#{shopId} AND table_number=#{number} " +
            "AND transac_status='unsettled' ORDER BY id FOR UPDATE")
    List<Order> lockUnsettledOrders(@Param("shopId") Integer shopId, @Param("number") String number);

    @Select("SELECT * FROM t_order WHERE shop_id=#{shopId} AND order_no=#{orderNo} LIMIT 1")
    Order findOrder(@Param("shopId") Integer shopId, @Param("orderNo") String orderNo);

    @Select("SELECT * FROM t_order WHERE shop_id=#{shopId} AND order_no=#{orderNo} LIMIT 1 FOR UPDATE")
    Order lockOrder(@Param("shopId") Integer shopId, @Param("orderNo") String orderNo);

    @Insert("INSERT INTO t_table(shop_id,number,status,open_time,out_time,order_no,amount) " +
            "VALUES(#{shop_id},#{number},#{status},#{open_time},#{out_time},#{order_no},#{amount})")
    @Options(useGeneratedKeys = true, keyProperty = "id")
    int insertTable(Table table);

    @Update("UPDATE t_table SET status=1,open_time=#{openedAt},out_time=NULL,order_no=NULL,amount=0 " +
            "WHERE id=#{id} AND shop_id=#{shopId} AND status=#{expectedStatus}")
    int openExistingTable(@Param("id") Integer id, @Param("shopId") Integer shopId,
                          @Param("expectedStatus") Integer expectedStatus, @Param("openedAt") Date openedAt);

    @Update("UPDATE t_table SET status=0,out_time=#{clearedAt},order_no=NULL,amount=0 " +
            "WHERE id=#{id} AND shop_id=#{shopId} AND status=#{expectedStatus}")
    int clearTable(@Param("id") Integer id, @Param("shopId") Integer shopId,
                   @Param("expectedStatus") Integer expectedStatus, @Param("clearedAt") Date clearedAt);

    @Update("UPDATE t_order SET order_receiving='off_order', off_time=IFNULL(off_time, #{clearedAt}) " +
            "WHERE shop_id=#{shopId} AND table_number=#{number} AND transac_status='success' " +
            "AND (order_receiving IS NULL OR order_receiving!='off_order')")
    int finishSettledOrdersOnTable(@Param("shopId") Integer shopId,
                                   @Param("number") String number,
                                   @Param("clearedAt") Date clearedAt);

    @Update("UPDATE t_order SET table_number=#{target}, master_order_no=#{masterOrderNo} WHERE shop_id=#{shopId} " +
            "AND table_number=#{source} AND transac_status='unsettled'")
    int moveUnsettledOrders(@Param("shopId") Integer shopId,
                            @Param("source") String source,
                            @Param("target") String target,
                            @Param("masterOrderNo") String masterOrderNo);

    default int moveUnsettledOrders(Integer shopId, String source, String target) {
        return moveUnsettledOrders(shopId, source, target, null);
    }

    @Update("UPDATE t_order SET table_number=#{target}, master_order_no=NULL WHERE id=#{id} AND shop_id=#{shopId} " +
            "AND table_number=#{source} AND transac_status='unsettled'")
    int moveOrder(@Param("id") Integer id, @Param("shopId") Integer shopId,
                  @Param("source") String source, @Param("target") String target);

    @Update("UPDATE t_table SET status=#{status},order_no=#{orderNo},amount=#{amount}," +
            "open_time=#{openedAt},out_time=#{outAt} WHERE id=#{id} AND shop_id=#{shopId}")
    int updateTableState(@Param("id") Integer id, @Param("shopId") Integer shopId,
                         @Param("status") Integer status, @Param("orderNo") String orderNo,
                         @Param("amount") Double amount, @Param("openedAt") Date openedAt,
                         @Param("outAt") Date outAt);
}
