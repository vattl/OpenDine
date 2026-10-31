package com.lanf.kds.service;

import com.baomidou.mybatisplus.core.conditions.query.QueryWrapper;
import com.lanf.kds.KdsItemStatus;
import com.lanf.kds.entity.KdsTicket;
import com.lanf.kds.mapper.KdsTicketMapper;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Service;

import java.util.Calendar;
import java.util.Date;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.stream.Collectors;

@Service
public class KdsStatsService {

    @Autowired
    private KdsTicketMapper ticketMapper;

    public Map<String, Object> todayStats(int shopId) {
        Calendar cal = Calendar.getInstance();
        cal.set(Calendar.HOUR_OF_DAY, 0);
        cal.set(Calendar.MINUTE, 0);
        cal.set(Calendar.SECOND, 0);
        cal.set(Calendar.MILLISECOND, 0);
        Date start = cal.getTime();

        List<KdsTicket> tickets = ticketMapper.selectList(new QueryWrapper<KdsTicket>()
                .eq("shop_id", shopId)
                .ge("created_at", start));
        Set<Integer> orderIds = tickets.stream()
                .map(KdsTicket::getOrder_id)
                .filter(id -> id != null)
                .collect(Collectors.toSet());
        int pending = 0;
        int cooking = 0;
        int done = 0;
        int voided = 0;
        for (KdsTicket t : tickets) {
            int s = t.getItem_status() != null ? t.getItem_status() : 0;
            if (s == KdsItemStatus.PENDING) {
                pending++;
            } else if (s == KdsItemStatus.COOKING) {
                cooking++;
            } else if (s == KdsItemStatus.DONE) {
                done++;
            } else if (s == KdsItemStatus.VOID) {
                voided++;
            }
        }
        Map<String, Object> m = new HashMap<>();
        m.put("shop_id", shopId);
        m.put("order_count", orderIds.size());
        m.put("ticket_count", tickets.size());
        m.put("pending_count", pending);
        m.put("cooking_count", cooking);
        m.put("done_count", done);
        m.put("void_count", voided);
        return m;
    }
}
