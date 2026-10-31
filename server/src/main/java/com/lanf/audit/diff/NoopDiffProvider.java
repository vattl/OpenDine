package com.lanf.audit.diff;

import java.util.Map;

/** 默认空实现：不捕获前后状态。 */
public class NoopDiffProvider implements DiffProvider {

    @Override
    public Map<String, Object> captureBefore(String targetId) {
        return null;
    }

    @Override
    public Map<String, Object> captureAfter(String targetId) {
        return null;
    }
}
