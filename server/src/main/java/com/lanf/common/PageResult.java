package com.lanf.common;

import java.util.List;

/**
 * 统一分页结构：{page, pageSize, total, items}（系统设置协调文档 §1）。
 */
public class PageResult {

    private int page;
    private int pageSize;
    private long total;
    private List<?> items;

    public static PageResult of(int page, int pageSize, long total, List<?> items) {
        PageResult p = new PageResult();
        p.page = page;
        p.pageSize = pageSize;
        p.total = total;
        p.items = items == null ? java.util.Collections.emptyList() : items;
        return p;
    }

    public int getPage() {
        return page;
    }

    public int getPageSize() {
        return pageSize;
    }

    public long getTotal() {
        return total;
    }

    public List<?> getItems() {
        return items;
    }
}
