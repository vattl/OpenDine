package com.lanf.kds.replication;

import lombok.Data;

import java.util.List;

@Data
public class KdsReplicationBatchRequest {
    private List<KdsReplicationEventRequest> events;
}
