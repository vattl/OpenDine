package com.lanf.service;

import com.baomidou.mybatisplus.extension.service.IService;
import com.lanf.entity.OperationLog;

public interface IOperationLogService extends IService<OperationLog> {

    /** 系统/定时任务触发的审计日志（无 admin_id）。 */
    void recordSystem(Integer shopId, String module, String action, String targetId, String requestSnapshot);
}
