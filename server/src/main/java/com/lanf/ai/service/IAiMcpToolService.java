package com.lanf.ai.service;

import java.util.List;
import java.util.Map;

public interface IAiMcpToolService {

    List<Map<String, Object>> listTools();

    Map<String, Object> executeTool(String toolName, Map<String, Object> arguments);
}
