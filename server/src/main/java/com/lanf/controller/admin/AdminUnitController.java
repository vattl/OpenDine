package com.lanf.controller.admin;

import com.lanf.audit.annotation.AuditLog;
import com.lanf.entity.Category;
import com.lanf.entity.Unit;
import com.lanf.entity.PageBean;
import com.lanf.entity.R;
import com.lanf.service.IUnitService;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import java.util.HashMap;
import java.util.List;
import java.util.Map;

/**
 * 菜品单位管理
 */
@RestController
@RequestMapping("/admin/unit")
public class AdminUnitController {

    @Autowired
    private IUnitService unitService;

    /**
     * 查询所有菜品单位
     * @return
     */
    @RequestMapping("/listAll")
    public R listAll(){
        List<Unit> list = unitService.list();
        Map<String,Object> resultMap=new HashMap<>();
        resultMap.put("unitList",list);
        return R.ok(resultMap);
    }

    /**
     * 添加
     * @param unit
     * @return
     */
    @PostMapping("/add")
    @AuditLog(module = "unit", action = "admin_unit_add")
    public R add(@RequestBody Unit unit){
        unit.setValue(unit.getLabel());
        unitService.save(unit);
        return R.ok();
    }


}
