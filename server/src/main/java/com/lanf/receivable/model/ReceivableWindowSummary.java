package com.lanf.receivable.model;

import lombok.AllArgsConstructor;
import lombok.Data;

import java.util.LinkedHashMap;
import java.util.Map;

@Data
@AllArgsConstructor
public class ReceivableWindowSummary {
    private long chargedFen;
    private long collectedFen;
    private long writeoffFen;
    private long reversedFen;
    private long outstandingFen;
    private long cutoffLedgerId;

    public static ReceivableWindowSummary empty() {
        return new ReceivableWindowSummary(0, 0, 0, 0, 0, 0);
    }

    public Map<String, Object> toMap() {
        Map<String, Object> map = new LinkedHashMap<>();
        map.put("charged_fen", chargedFen);
        map.put("collected_fen", collectedFen);
        map.put("writeoff_fen", writeoffFen);
        map.put("reversed_fen", reversedFen);
        map.put("outstanding_fen", outstandingFen);
        map.put("cutoff_ledger_id", cutoffLedgerId);
        return map;
    }
}
