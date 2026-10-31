package com.lanf.printing.model;

import lombok.Data;
import java.util.ArrayList;
import java.util.List;

/** Read-only result of the same rule/device/template rendering used by dispatch. */
@Data
public class PrintResolvedPreview {
    private Long ruleId;
    private Long deviceId;
    private String deviceName;
    private String transport;
    private Long templateId;
    private String templateCode;
    private String paperSize;
    private List<String> contents = new ArrayList<>();
    private List<String> bindingWarnings = new ArrayList<>();
    private List<String> capabilityWarnings = new ArrayList<>();
}
