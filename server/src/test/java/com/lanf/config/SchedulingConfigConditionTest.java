package com.lanf.config;

import org.junit.jupiter.api.Test;
import org.springframework.boot.test.context.runner.ApplicationContextRunner;
import org.springframework.boot.task.TaskSchedulerBuilder;

import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertTrue;

class SchedulingConfigConditionTest {

    private final ApplicationContextRunner contextRunner = new ApplicationContextRunner()
            .withBean(TaskSchedulerBuilder.class, TaskSchedulerBuilder::new)
            .withUserConfiguration(SchedulingConfig.class);

    @Test
    void schedulingIsEnabledByDefaultForProductionCompatibility() {
        contextRunner.run(context -> assertTrue(context.containsBean("schedulingConfig")));
    }

    @Test
    void schedulingCanBeDisabledForDebugProfile() {
        contextRunner
                .withPropertyValues("app.scheduling.enabled=false")
                .run(context -> assertFalse(context.containsBean("schedulingConfig")));
    }
}
