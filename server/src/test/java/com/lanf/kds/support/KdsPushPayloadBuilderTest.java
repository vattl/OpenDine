package com.lanf.kds.support;

import com.lanf.entity.OrderDetail;
import org.junit.jupiter.api.Test;

import java.util.Collections;
import java.util.Map;

import static org.junit.jupiter.api.Assertions.assertEquals;

class KdsPushPayloadBuilderTest {

    @Test
    void itemPayloadPreservesComboHierarchy() {
        OrderDetail component = new OrderDetail();
        component.setId(22);
        component.setDish_id(201);
        component.setName("烤羊肉串");
        component.setQuantity("2");
        component.setLine_type("combo_component");
        component.setCombo_id(9L);
        component.setCombo_instance_id("combo-instance-1");
        component.setParent_detail_id(21);

        Map<String, Object> item = KdsPushPayloadBuilder
                .toItemList(Collections.singletonList(component)).get(0);

        assertEquals("combo_component", item.get("line_type"));
        assertEquals(9L, item.get("combo_id"));
        assertEquals("combo-instance-1", item.get("combo_instance_id"));
        assertEquals(21, item.get("parent_detail_id"));
    }
}
