package com.lanf.dto;

import lombok.AllArgsConstructor;
import lombok.Data;
import lombok.NoArgsConstructor;

@Data
@NoArgsConstructor
@AllArgsConstructor
public class OfflineCollectTokenPayload {
    private int shopId;
    private String channel;
    private String merchantId;
}
