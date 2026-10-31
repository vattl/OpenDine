package com.lanf.kds;

import com.lanf.kds.entity.KdsDevice;

import java.util.ArrayList;
import java.util.Arrays;
import java.util.Collections;
import java.util.List;

/**
 * 厨显登录可选工作流程：配菜 prep、制作 cook、传菜 serve（可多选）。
 */
public final class KdsWorkflow {

    public static final String PREP = "prep";
    public static final String COOK = "cook";
    public static final String SERVE = "serve";

    private static final List<String> ALL = Collections.unmodifiableList(
            Arrays.asList(PREP, COOK, SERVE));

    private KdsWorkflow() {
    }

    public static List<String> normalizeList(List<String> raw) {
        if (raw == null || raw.isEmpty()) {
            return Collections.emptyList();
        }
        List<String> out = new ArrayList<>();
        for (String s : raw) {
            if (s == null) {
                continue;
            }
            String t = s.trim().toLowerCase();
            if (ALL.contains(t) && !out.contains(t)) {
                out.add(t);
            }
        }
        return out;
    }

    public static List<String> resolveForDevice(KdsDevice device) {
        return resolveForDevice(device, true);
    }

    public static List<String> resolveForDevice(KdsDevice device, boolean prepEnabled) {
        List<String> rawWorkflows = null;
        if (device != null && device.getWorkflows() != null && !device.getWorkflows().isEmpty()) {
            rawWorkflows = device.getWorkflows();
        } else {
            String tag = device != null ? device.getScreen_tag() : null;
            if (KdsScreenTag.SKEWER_AGGREGATE.equals(tag)) {
                rawWorkflows = prepEnabled ? Collections.singletonList(PREP) : Collections.emptyList();
            } else if (KdsScreenTag.EXPEDITION.equals(tag)) {
                rawWorkflows = Collections.singletonList(SERVE);
            } else if (KdsScreenTag.MEAT_GRILL.equals(tag)
                    || KdsScreenTag.VEG_GRILL.equals(tag)
                    || KdsScreenTag.SEAFOOD_SPECIAL.equals(tag)) {
                rawWorkflows = Collections.singletonList(COOK);
            } else {
                rawWorkflows = prepEnabled ? new ArrayList<>(ALL) : new ArrayList<>(Arrays.asList(COOK, SERVE));
            }
        }
        if (!prepEnabled) {
            List<String> filtered = new ArrayList<>();
            for (String w : rawWorkflows) {
                if (!PREP.equalsIgnoreCase(w)) {
                    filtered.add(w);
                }
            }
            return filtered;
        }
        return new ArrayList<>(rawWorkflows);
    }

    public static boolean canAccessQueue(KdsDevice device, String queue) {
        return canAccessQueue(device, queue, true);
    }

    public static boolean canAccessQueue(KdsDevice device, String queue, boolean prepEnabled) {
        if (!prepEnabled && KdsWorkflowQueue.PENDING_PREP.equals(queue)) {
            return false;
        }
        List<String> workflows = resolveForDevice(device, prepEnabled);
        if (KdsWorkflowQueue.PENDING_PREP.equals(queue)) {
            return workflows.contains(PREP);
        }
        if (KdsWorkflowQueue.PENDING_COOK.equals(queue)) {
            return workflows.contains(COOK);
        }
        if (KdsWorkflowQueue.READY_SERVE.equals(queue)) {
            return workflows.contains(SERVE);
        }
        return true;
    }

    public static List<String> visibleQueues(KdsDevice device) {
        return visibleQueues(device, true);
    }

    public static List<String> visibleQueues(KdsDevice device, boolean prepEnabled) {
        List<String> queues = new ArrayList<>();
        List<String> workflows = resolveForDevice(device, prepEnabled);
        if (prepEnabled && workflows.contains(PREP)) {
            queues.add(KdsWorkflowQueue.PENDING_PREP);
        }
        if (workflows.contains(COOK)) {
            queues.add(KdsWorkflowQueue.PENDING_COOK);
        }
        if (workflows.contains(SERVE)) {
            queues.add(KdsWorkflowQueue.READY_SERVE);
        }
        queues.add(KdsWorkflowQueue.DONE);
        return queues;
    }
}
