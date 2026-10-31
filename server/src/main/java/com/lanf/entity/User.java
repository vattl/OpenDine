package com.lanf.entity;

import com.baomidou.mybatisplus.annotation.TableName;
import com.fasterxml.jackson.databind.annotation.JsonSerialize;
import lombok.Data;

import java.math.BigDecimal;
import java.util.Date;
import java.util.List;


/**
 * 用户表
 */
@TableName("t_user")
@Data
public class User {

    private Integer id; // 编号

    private String avatar;

    private String name; // 用户名称

    private String openid; // 用户唯一标识

    private String phone; // 手机号

    private Integer points; // 积分

    /** 账户总余额（元）= principal_balance + gift_balance；小程序等只读此字段即可显示正确总额 */
    private BigDecimal balance;

    /** 本金（元），可消费本金分账；与 gift_balance 之和应等于 balance */
    private BigDecimal principal_balance;

    /** 赠送金余额（元） */
    private BigDecimal gift_balance;

    private String session_key; // 用户会话

    @JsonSerialize(using=CustomDateTimeSerializer.class)
    private Date time;

    private Integer user_type; //用户类型：0普通/1会员

    private Integer level; //会员等级

    private String invite_code;

    /** 生日，格式如 yyyy-MM-dd 或 MM-dd，对应 t_user.birthday varchar(10) */
    private String birthday;

    /** 昵称（别名/扩展，与 name 双向同步，非数据库列） */
    @com.baomidou.mybatisplus.annotation.TableField(exist = false)
    private String nickname;

    public String getNickname() {
        return this.nickname != null ? this.nickname : this.name;
    }

    public void setNickname(String nickname) {
        this.nickname = nickname;
        if (nickname != null && !nickname.trim().isEmpty()) {
            this.name = nickname.trim();
        }
    }

    public void setName(String name) {
        this.name = name;
        this.nickname = name;
    }

}
