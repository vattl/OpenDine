package com.lanf.payment.entity;

import com.baomidou.mybatisplus.annotation.FieldStrategy;
import com.baomidou.mybatisplus.annotation.TableField;
import org.junit.jupiter.api.Test;

import java.lang.reflect.Field;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertNotNull;

class WechatNativePaymentAttemptEntityTest {

    @Test
    void activeKeyMustBeIncludedInUpdatesWhenClearedToNull() throws Exception {
        Field field = WechatNativePaymentAttemptEntity.class.getDeclaredField("active_key");
        TableField mapping = field.getAnnotation(TableField.class);

        assertNotNull(mapping, "active_key requires an explicit update strategy");
        assertEquals(FieldStrategy.IGNORED, mapping.updateStrategy(),
                "terminal Native attempts must persist active_key = NULL");
    }
}
