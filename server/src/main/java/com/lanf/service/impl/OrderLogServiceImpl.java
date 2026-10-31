package com.lanf.service.impl;

import com.baomidou.mybatisplus.extension.service.impl.ServiceImpl;
import com.lanf.entity.OrderLog;
import com.lanf.mapper.OrderLogMapper;
import com.lanf.service.IOrderLogService;
import org.springframework.stereotype.Service;

@Service
public class OrderLogServiceImpl extends ServiceImpl<OrderLogMapper, OrderLog> implements IOrderLogService {
}
