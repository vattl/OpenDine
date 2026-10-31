package com.lanf.event;

import org.springframework.context.ApplicationEvent;

/**
 * 后台菜品库变更（上下架、保存、删除、排序等），用于失效 AI 在售菜单缓存等。
 */
public class DishCatalogChangedEvent extends ApplicationEvent {

    private final String action;
    private final Integer dishId;
    private final String dishName;
    private final Boolean onsale;

    public DishCatalogChangedEvent(Object source, String action, Integer dishId, String dishName, Boolean onsale) {
        super(source);
        this.action = action;
        this.dishId = dishId;
        this.dishName = dishName;
        this.onsale = onsale;
    }

    public String getAction() {
        return action;
    }

    public Integer getDishId() {
        return dishId;
    }

    public String getDishName() {
        return dishName;
    }

    public Boolean getOnsale() {
        return onsale;
    }
}
