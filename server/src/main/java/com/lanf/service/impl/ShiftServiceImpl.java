package com.lanf.service.impl;

import com.baomidou.mybatisplus.extension.service.impl.ServiceImpl;
import com.lanf.entity.Shift;
import com.lanf.mapper.ShiftMapper;
import com.lanf.service.IShiftService;
import org.springframework.stereotype.Service;

@Service
public class ShiftServiceImpl extends ServiceImpl<ShiftMapper, Shift> implements IShiftService {
}
