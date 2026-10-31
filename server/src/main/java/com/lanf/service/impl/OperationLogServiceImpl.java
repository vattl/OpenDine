package com.lanf.service.impl;

import com.baomidou.mybatisplus.extension.service.impl.ServiceImpl;
import com.lanf.entity.OperationLog;
import com.lanf.mapper.OperationLogMapper;
import com.lanf.service.IOperationLogService;
import org.springframework.stereotype.Service;

@Service
public class OperationLogServiceImpl extends ServiceImpl<OperationLogMapper, OperationLog> implements IOperationLogService {

    @Override
    public void recordSystem(Integer shopId, String module, String action, String targetId, String requestSnapshot) {
        OperationLog row = new OperationLog();
        row.setShop_id(shopId);
        row.setModule(module);
        row.setAction(action);
        row.setTarget_id(targetId);
        row.setRequest_snapshot(requestSnapshot);
        save(row);
    }
}
