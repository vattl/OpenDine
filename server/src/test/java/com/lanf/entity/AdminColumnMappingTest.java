package com.lanf.entity;

import com.baomidou.mybatisplus.annotation.TableField;
import org.junit.jupiter.api.Test;

import java.lang.reflect.Field;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertNotNull;

class AdminColumnMappingTest {

    @Test
    void tokenVersionUsesTheMigratedSnakeCaseColumn() throws Exception {
        Field field = Admin.class.getDeclaredField("tokenVersion");
        TableField mapping = field.getAnnotation(TableField.class);
        assertNotNull(mapping);
        assertEquals("token_version", mapping.value());
    }

    @Test
    void employeeColumnsUseSnakeCaseMapping() throws Exception {
        Field workNoField = Admin.class.getDeclaredField("workNo");
        TableField workNoMapping = workNoField.getAnnotation(TableField.class);
        assertNotNull(workNoMapping);
        assertEquals("work_no", workNoMapping.value());

        Field realNameField = Admin.class.getDeclaredField("realName");
        TableField realNameMapping = realNameField.getAnnotation(TableField.class);
        assertNotNull(realNameMapping);
        assertEquals("real_name", realNameMapping.value());

        Field jobTitleField = Admin.class.getDeclaredField("jobTitle");
        TableField jobTitleMapping = jobTitleField.getAnnotation(TableField.class);
        assertNotNull(jobTitleMapping);
        assertEquals("job_title", jobTitleMapping.value());
    }
}
