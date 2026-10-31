package com.lanf.entity;

import com.baomidou.mybatisplus.annotation.IdType;
import com.baomidou.mybatisplus.annotation.TableField;
import com.baomidou.mybatisplus.annotation.TableId;
import com.baomidou.mybatisplus.annotation.TableName;
import lombok.Data;

/**
 * 管理员实体
 */
@TableName("t_admin")
@Data
public class Admin {

    @TableId(type = IdType.AUTO)
    private Integer id; // 编号

    private String userName; // 用户名

    /** 员工工号，用于工号登录 */
    @TableField("work_no")
    @com.fasterxml.jackson.annotation.JsonProperty("workNo")
    @com.fasterxml.jackson.annotation.JsonAlias({"work_no", "workNo", "jobNumber", "job_number"})
    private String workNo;

    /** 员工姓名，系统内所有操作人展示优先采用此姓名 */
    @TableField("real_name")
    @com.fasterxml.jackson.annotation.JsonProperty("realName")
    @com.fasterxml.jackson.annotation.JsonAlias({"real_name", "realName", "name"})
    private String realName;

    /** 员工岗位/职位，例如店长、收银员、服务员、后厨等 */
    @TableField("job_title")
    @com.fasterxml.jackson.annotation.JsonProperty("jobTitle")
    @com.fasterxml.jackson.annotation.JsonAlias({"job_title", "jobTitle", "post", "position"})
    private String jobTitle;

    private String password; // 密码

    /** Incremented whenever all existing sessions for this administrator must be revoked. */
    @TableField("token_version")
    private Integer tokenVersion;

    public static final String STATUS_ACTIVE = "ACTIVE";
    public static final String STATUS_DISABLED = "DISABLED";
    public static final String STATUS_LOCKED = "LOCKED";
    public static final String STATUS_RESIGNED = "RESIGNED";

    /** 账户状态: ACTIVE, DISABLED, LOCKED, RESIGNED */
    @TableField("account_status")
    private String accountStatus;

    /** 权限版本号，角色/范围变更时递增 */
    @TableField("permission_version")
    private Long permissionVersion;

    /** 连续登录失败次数 */
    @TableField("failed_login_count")
    private Integer failedLoginCount;

    /** 账号锁定截止时间 */
    @TableField("locked_until")
    private java.util.Date lockedUntil;

    /** 最后登录时间 */
    @TableField("last_login_at")
    private java.util.Date lastLoginAt;

    /** 最后登录IP */
    @TableField("last_login_ip")
    private String lastLoginIp;

    /** 密码修改时间 */
    @TableField("password_changed_at")
    private java.util.Date passwordChangedAt;

    /** 强制下线时间，签发早于此时的JWT失效 */
    @TableField("force_logout_at")
    private java.util.Date forceLogoutAt;

    /** 店长授权PIN码哈希 */
    @TableField("manager_pin_hash")
    private String managerPinHash;

    /** PIN连续失败次数 */
    @TableField("pin_failed_count")
    private Integer pinFailedCount;

    /** PIN锁定截止时间 */
    @TableField("pin_locked_until")
    private java.util.Date pinLockedUntil;

    @TableField(select = false)
    private String newPassword; // 新密码

    public String getWork_no() {
        return workNo;
    }

    public void setWork_no(String work_no) {
        this.workNo = work_no;
    }

    public String getReal_name() {
        return realName;
    }

    public void setReal_name(String real_name) {
        this.realName = real_name;
    }

    public String getJob_title() {
        return jobTitle;
    }

    public void setJob_title(String job_title) {
        this.jobTitle = job_title;
    }
}
