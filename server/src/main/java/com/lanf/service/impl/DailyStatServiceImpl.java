package com.lanf.service.impl;

import com.baomidou.mybatisplus.extension.service.impl.ServiceImpl;
import com.lanf.entity.DailyStat;
import com.lanf.mapper.DailyStatMapper;
import com.lanf.service.IDailyStatService;
import org.springframework.stereotype.Service;

@Service
public class DailyStatServiceImpl extends ServiceImpl<DailyStatMapper, DailyStat> implements IDailyStatService {
}
