// 邀请码返回DTO
package com.lanf.dto;

import lombok.Data;

import java.math.BigDecimal;
import java.time.LocalDateTime;

@Data
public class InviteCodeDTO {
    private String invite_code; // 专属邀请码
}

