package com.lanf.dto;

import com.lanf.entity.Table;
import lombok.Data;

@Data
public class CashierTableOperationResult {
    private boolean success;
    private boolean idempotent;
    private int code;
    private String message;
    private Table table;

    public static CashierTableOperationResult success(String message, Table table) {
        CashierTableOperationResult result = new CashierTableOperationResult();
        result.success = true;
        result.code = 0;
        result.message = message;
        result.table = table;
        return result;
    }

    public static CashierTableOperationResult rejected(int code, String message) {
        CashierTableOperationResult result = new CashierTableOperationResult();
        result.success = false;
        result.code = code;
        result.message = message;
        return result;
    }
}
