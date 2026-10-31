package com.lanf.mapper;

import com.baomidou.mybatisplus.core.mapper.BaseMapper;
import com.lanf.entity.LedgerBackfillLog;
import org.apache.ibatis.annotations.Mapper;

/**
 * 历史账本回填日志 Mapper
 */
@Mapper
public interface LedgerBackfillLogMapper extends BaseMapper<LedgerBackfillLog> {
}
