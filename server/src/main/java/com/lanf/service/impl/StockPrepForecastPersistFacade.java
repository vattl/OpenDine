package com.lanf.service.impl;

import com.lanf.entity.StockPrepForecastDay;
import com.lanf.entity.StockPrepForecastDish;
import com.lanf.entity.StockPrepForecastRun;
import com.lanf.mapper.StockPrepForecastDayMapper;
import com.lanf.mapper.StockPrepForecastDishMapper;
import com.lanf.mapper.StockPrepForecastRunMapper;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.util.List;

@Service
public class StockPrepForecastPersistFacade {

    @Autowired
    private StockPrepForecastRunMapper runMapper;
    @Autowired
    private StockPrepForecastDayMapper dayMapper;
    @Autowired
    private StockPrepForecastDishMapper dishMapper;

    @Transactional(rollbackFor = Exception.class)
    public Long saveRunWithDetails(StockPrepForecastRun run, List<StockPrepForecastDay> days, List<StockPrepForecastDish> dishes) {
        runMapper.insert(run);
        Long runId = run.getId();
        if (runId == null) {
            throw new IllegalStateException("备货预测批次插入后未获得主键");
        }
        for (StockPrepForecastDay d : days) {
            d.setRun_id(runId);
            dayMapper.insert(d);
        }
        for (StockPrepForecastDish di : dishes) {
            di.setRun_id(runId);
            dishMapper.insert(di);
        }
        return runId;
    }
}
