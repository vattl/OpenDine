package com.lanf.kds.replication;

import com.fasterxml.jackson.annotation.JsonAlias;
import com.fasterxml.jackson.databind.JsonNode;
import lombok.Data;

@Data
public class KdsReplicationEventRequest {

    @JsonAlias("event_id")
    private String eventId;

    @JsonAlias("event_type")
    private String eventType;

    @JsonAlias("aggregate_key")
    private String aggregateKey;

    @JsonAlias("occurred_at_ms")
    private Long occurredAtMs;

    private JsonNode payload;
}
