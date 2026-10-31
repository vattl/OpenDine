package com.lanf.ai.service;

import com.lanf.ai.dto.AiMenuSnapshotDTO;

public interface IAiMenuAdapterService {
    /**
     * 获取指定门店的当前真实在售菜单快照及 SHA-256 版本 Hash
     * @param shopId 门店ID
     * @return 菜单快照 DTO
     */
    AiMenuSnapshotDTO getStoreMenuSnapshot(Integer shopId);
}
