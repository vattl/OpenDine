-- Run the preflight query first. Resolve any historical duplicates before adding the constraint.
SELECT order_no, COUNT(*) AS duplicate_count
FROM t_order
GROUP BY order_no
HAVING COUNT(*) > 1;

-- The unique index is the cross-process guard for ORD + yyyyMMddHHmmss + 3 digits.
ALTER TABLE t_order
  DROP INDEX order_no,
  ADD UNIQUE INDEX uk_order_order_no (order_no);
