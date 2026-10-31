package com.lanf.controller;

import com.lanf.entity.R;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

/**
 * 帮助与 FAQ（openapi 可选接口，当前提供内置内容）。
 */
@RestController
@RequestMapping("/help")
public class HelpController {

    @GetMapping("/list")
    public R list(@RequestParam(required = false) String category) {
        List<Map<String, Object>> list = new ArrayList<>();
        list.add(item(1, "下单后多久出餐？", "common"));
        list.add(item(2, "如何申请退款？", "payment"));
        list.add(item(3, "如何联系门店？", "common"));
        if (category != null && !category.trim().isEmpty()) {
            String c = category.trim().toLowerCase();
            list.removeIf(it -> !c.equals(String.valueOf(it.get("category")).toLowerCase()));
        }
        return R.ok().put("list", list);
    }

    @GetMapping("/detail/{id}")
    public R detail(@PathVariable Integer id) {
        if (id == null) {
            return R.error("参数错误");
        }
        Map<String, Object> data = new HashMap<>();
        data.put("id", id);
        data.put("title", "帮助说明");
        data.put("content", "请联系门店或客服获取更多帮助。");
        return R.ok().put("data", data);
    }

    private Map<String, Object> item(int id, String title, String category) {
        Map<String, Object> m = new HashMap<>();
        m.put("id", id);
        m.put("title", title);
        m.put("category", category);
        return m;
    }
}
