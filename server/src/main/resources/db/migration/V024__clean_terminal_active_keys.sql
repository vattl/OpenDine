-- Clean residual active_key from terminal state attempts to prevent duplicate key conflicts
UPDATE t_wechat_native_payment_attempt
SET active_key = NULL
WHERE active_key IS NOT NULL AND status IN ('CLOSED', 'SUCCESS', 'PAYERROR', 'REVOKED');

UPDATE t_wechat_micropay_attempt
SET active_key = NULL
WHERE active_key IS NOT NULL AND status IN ('CLOSED', 'SUCCESS', 'FAILED', 'REVERSED');
