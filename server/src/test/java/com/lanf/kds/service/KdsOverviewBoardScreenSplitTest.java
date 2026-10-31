package com.lanf.kds.service;

import com.baomidou.mybatisplus.core.conditions.query.QueryWrapper;
import com.lanf.kds.entity.KdsShopConfig;
import com.lanf.kds.entity.KdsTicket;
import com.lanf.kds.mapper.KdsTicketMapper;
import com.lanf.service.IDishService;
import com.lanf.service.IOrderDetailService;
import com.lanf.service.IOrderService;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;
import org.springframework.test.util.ReflectionTestUtils;

import java.util.Collection;
import java.util.Collections;
import java.util.HashSet;
import java.util.Map;
import java.util.Set;

import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyInt;
import static org.mockito.Mockito.atLeastOnce;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

/**
 * D026：统一看板取数按设备可见岗过滤（screenTags → .in("screen_tag", ...)）。
 */
class KdsOverviewBoardScreenSplitTest {

    private KdsOverviewBoardService service;
    private KdsTicketMapper ticketMapper;

    @BeforeEach
    void setUp() {
        service = new KdsOverviewBoardService();
        ticketMapper = mock(KdsTicketMapper.class);
        ReflectionTestUtils.setField(service, "ticketMapper", ticketMapper);
        ReflectionTestUtils.setField(service, "orderService", mock(IOrderService.class));
        ReflectionTestUtils.setField(service, "orderDetailService", mock(IOrderDetailService.class));
        ReflectionTestUtils.setField(service, "configService", mock(KdsConfigService.class));
        ReflectionTestUtils.setField(service, "dishService", mock(IDishService.class));
        ReflectionTestUtils.setField(service, "flowBatchService", mock(KdsFlowBatchService.class));
        ReflectionTestUtils.setField(service, "servingDurationService", mock(KdsDishServingDurationService.class));

        KdsConfigService configService = (KdsConfigService) ReflectionTestUtils.getField(service, "configService");
        when(configService.getOrDefault(anyInt())).thenReturn(new KdsShopConfig());
        // 空工单：不触发 order/detail 聚合，便于只验证过滤条件
        when(ticketMapper.selectList(any())).thenReturn(Collections.emptyList());
    }

    /** 捕获 countWorkflowQueues 内 selectList 的 QueryWrapper 并校验 screen_tag IN 条件。 */
    private QueryWrapper<KdsTicket> captureWrapper() {
        ArgumentCaptor<QueryWrapper<KdsTicket>> captor = ArgumentCaptor.forClass(QueryWrapper.class);
        verify(ticketMapper, atLeastOnce()).selectList(captor.capture());
        QueryWrapper<KdsTicket> qw = captor.getAllValues().get(0);
        System.out.println("DIAG SQLSEG=" + qw.getSqlSegment());
        System.out.println("DIAG PARAMS=" + qw.getParamNameValuePairs());
        return qw;
    }

    private static boolean containsTag(QueryWrapper<KdsTicket> qw, String tag) {
        Map<String, Object> params = qw.getParamNameValuePairs();
        if (params == null) {
            return false;
        }
        for (Object v : params.values()) {
            if (v instanceof Collection) {
                for (Object o : (Collection<?>) v) {
                    if (tag.equals(o)) {
                        return true;
                    }
                }
            } else if (tag.equals(v)) {
                return true;
            }
        }
        return false;
    }

    @Test
    @DisplayName("未配置（null）→ 查询条件含烤制三岗")
    void nullScreenTagsQueriesAllThreeGrill() {
        service.countWorkflowQueues(1, null, null, null);
        QueryWrapper<KdsTicket> qw = captureWrapper();
        assertTrue(containsTag(qw, "meat_grill"));
        assertTrue(containsTag(qw, "veg_grill"));
        assertTrue(containsTag(qw, "seafood_special"));
    }

    @Test
    @DisplayName("配置 [meat_grill] → 只查荤菜岗，排除素菜/海鲜")
    void configuredScreenTagsFilterToSubset() {
        Set<String> tags = new HashSet<>(Collections.singletonList("meat_grill"));
        service.countWorkflowQueues(1, null, null, null, tags);
        QueryWrapper<KdsTicket> qw = captureWrapper();
        assertTrue(containsTag(qw, "meat_grill"));
        assertFalse(containsTag(qw, "veg_grill"));
        assertFalse(containsTag(qw, "seafood_special"));
    }

    @Test
    @DisplayName("配置 [veg_grill, seafood_special] → 查两岗，排除荤菜")
    void configuredScreenTagsMultiple() {
        Set<String> tags = new HashSet<>(java.util.Arrays.asList("veg_grill", "seafood_special"));
        service.countWorkflowQueues(1, null, null, null, tags);
        QueryWrapper<KdsTicket> qw = captureWrapper();
        assertTrue(containsTag(qw, "veg_grill"));
        assertTrue(containsTag(qw, "seafood_special"));
        assertFalse(containsTag(qw, "meat_grill"));
    }

    @Test
    @DisplayName("空集合等价于默认三岗全选")
    void emptyScreenTagsFallsBackToThreeGrill() {
        service.countWorkflowQueues(1, null, null, null, Collections.emptySet());
        QueryWrapper<KdsTicket> qw = captureWrapper();
        assertTrue(containsTag(qw, "meat_grill"));
        assertTrue(containsTag(qw, "seafood_special"));
    }
}
