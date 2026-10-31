package com.lanf.service.impl;

import com.baomidou.mybatisplus.extension.service.impl.ServiceImpl;
import com.lanf.entity.StockOut;
import com.lanf.mapper.StockOutMapper;
import com.lanf.service.IStockOutService;
import org.springframework.stereotype.Service;

@Service
public class StockOutServiceImpl extends ServiceImpl<StockOutMapper, StockOut> implements IStockOutService {
}
