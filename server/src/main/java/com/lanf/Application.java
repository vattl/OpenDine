package com.lanf;

import org.mybatis.spring.annotation.MapperScan;
import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;

@SpringBootApplication
@MapperScan({"com.lanf.mapper", "com.lanf.kds.mapper", "com.lanf.payment.mapper",
        "com.lanf.settings.mapper", "com.lanf.printing.mapper", "com.lanf.notify.mapper",
        "com.lanf.marketing.mapper", "com.lanf.access.mapper", "com.lanf.inventory.mapper",
        "com.lanf.report.mapper", "com.lanf.adminlog.mapper", "com.lanf.receivable.mapper",
        "com.lanf.ai.mapper"})
public class Application {

    public static void main(String[] args) {
        SpringApplication.run(Application.class, args);
    }

}
