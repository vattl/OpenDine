package com.lanf.service.impl;

import com.baomidou.mybatisplus.extension.service.impl.ServiceImpl;
import com.lanf.entity.StockIn;
import com.lanf.mapper.StockInMapper;
import com.lanf.service.IStockInService;
import org.springframework.stereotype.Service;

@Service
public class StockInServiceImpl extends ServiceImpl<StockInMapper, StockIn> implements IStockInService {
}
