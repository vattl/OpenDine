package com.lanf.kds.service;

import com.baomidou.mybatisplus.core.conditions.query.QueryWrapper;
import com.lanf.entity.Order;
import com.lanf.kds.entity.KdsOrder;
import com.lanf.kds.mapper.KdsOrderMapper;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Service;

import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.stream.Collectors;

@Service
public class KdsOrderEnrichService {

    @Autowired
    private KdsOrderMapper kdsOrderMapper;

    public void enrichOrders(List<Order> orders) {
        if (orders == null || orders.isEmpty()) {
            return;
        }
        List<Integer> ids = orders.stream().map(Order::getId).filter(id -> id != null).collect(Collectors.toList());
        if (ids.isEmpty()) {
            return;
        }
        List<KdsOrder> kdsRows = kdsOrderMapper.selectList(new QueryWrapper<KdsOrder>().in("order_id", ids));
        Map<Integer, Integer> statusMap = new HashMap<>();
        if (kdsRows != null) {
            for (KdsOrder ko : kdsRows) {
                statusMap.put(ko.getOrder_id(), ko.getKds_order_status());
            }
        }
        for (Order o : orders) {
            if (o != null && o.getId() != null) {
                o.setKds_order_status(statusMap.get(o.getId()));
            }
        }
    }
}
