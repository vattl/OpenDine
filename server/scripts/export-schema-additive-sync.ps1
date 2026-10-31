# 从 debug 库（127.0.0.1:3307/db_diancan_debug）生成「幂等增量同步」SQL：
#   - 缺失的表：CREATE TABLE IF NOT EXISTS 全量结构（不含数据、不含自增当前值）
#   - 已存在的表：逐列「不存在才 ADD COLUMN」（守护过程 + information_schema 判定）
# 脚本对已有数据零影响，可在云端库重复执行。
$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "debug-env-common.ps1")
Import-DebugEnv (Join-Path (Get-DebugRepoRoot) ".env.debug")

$mysql = "C:\Program Files\MySQL\MySQL Server 8.0\bin\mysql.exe"
$mysqldump = "C:\Program Files\MySQL\MySQL Server 8.0\bin\mysqldump.exe"
$outFile = Join-Path (Get-DebugRepoRoot) "docs\db_schema_additive_sync.sql"
$prevPwd = $env:MYSQL_PWD
$env:MYSQL_PWD = $env:DEBUG_DB_PASSWORD
try {
    # 1) 结构导出（仅 DDL），去掉 DROP TABLE 与 AUTO_INCREMENT 当前值，改为 IF NOT EXISTS
    $dump = & $mysqldump --protocol=tcp -h 127.0.0.1 -P 3307 -u $env:DEBUG_DB_USERNAME `
            --no-data --skip-add-drop-table --skip-add-locks --skip-disable-keys `
            --skip-comments --compact db_diancan_debug 2>$null | Out-String
    if ($LASTEXITCODE -ne 0) { throw "mysqldump failed" }
    $dump = [regex]::Replace($dump, 'CREATE TABLE `', 'CREATE TABLE IF NOT EXISTS `')
    $dump = [regex]::Replace($dump, ' AUTO_INCREMENT=\d+', '')

    # 2) 逐列生成守护 CALL（在 debug 库上展开为字面量，云端执行时按云端 information_schema 判定）
    $colSql = @'
SELECT CONCAT(
  'CALL `p_add_col_if_missing`(', QUOTE(TABLE_NAME), ',', QUOTE(COLUMN_NAME), ',',
  QUOTE(CONCAT(
    '`', COLUMN_NAME, '` ', COLUMN_TYPE,
    IF(EXTRA LIKE '%auto_increment%', ' NOT NULL AUTO_INCREMENT', IF(IS_NULLABLE='YES', ' NULL', ' NOT NULL')),
    CASE
      WHEN EXTRA LIKE '%auto_increment%' THEN ''
      WHEN COLUMN_DEFAULT IS NULL THEN IF(IS_NULLABLE='YES', ' DEFAULT NULL', '')
      WHEN UPPER(COLUMN_DEFAULT) LIKE 'CURRENT_TIMESTAMP%' THEN CONCAT(' DEFAULT ', UPPER(COLUMN_DEFAULT))
      WHEN DATA_TYPE IN ('int','bigint','tinyint','smallint','mediumint','decimal','float','double','bit','year') THEN CONCAT(' DEFAULT ', COLUMN_DEFAULT)
      ELSE CONCAT(' DEFAULT ', QUOTE(COLUMN_DEFAULT))
    END,
    IF(EXTRA LIKE '%on update CURRENT_TIMESTAMP%', ' ON UPDATE CURRENT_TIMESTAMP', ''),
    IF(COLUMN_COMMENT = '', '', CONCAT(' COMMENT ', QUOTE(COLUMN_COMMENT))),
    IFNULL(CONCAT(' AFTER `', LAG(COLUMN_NAME) OVER (PARTITION BY TABLE_NAME ORDER BY ORDINAL_POSITION), '`'), ' FIRST')
  )), ');')
FROM information_schema.COLUMNS
WHERE TABLE_SCHEMA = 'db_diancan_debug'
ORDER BY TABLE_NAME, ORDINAL_POSITION;
'@
    $calls = & $mysql --protocol=tcp -h 127.0.0.1 -P 3307 -u $env:DEBUG_DB_USERNAME db_diancan_debug `
            --default-character-set=utf8mb4 --batch --skip-column-names --raw -e $colSql 2>$null
    if ($LASTEXITCODE -ne 0) { throw "column query failed" }

    $header = @"
-- ============================================================
-- 结构增量同步脚本（debug -> cloud），生成于 $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
-- 源：127.0.0.1:3307/db_diancan_debug
-- 语义：
--   1) 云端缺失的表整表创建（不含数据）；
--   2) 云端已存在的表仅补充缺失字段（逐列守护，已存在则跳过）；
--   3) 不 DROP、不清空、不修改任何已有列/数据；可重复执行。
-- 使用：mysql -h <cloud-host> -u <user> -p <cloud_db> < db_schema_additive_sync.sql
-- 注意：不会为已存在的表补索引/外键；唯一键等约束仅随新建表生效。
-- ============================================================
SET FOREIGN_KEY_CHECKS=0;

DROP PROCEDURE IF EXISTS ``p_add_col_if_missing``;
DELIMITER `$
`$
CREATE PROCEDURE ``p_add_col_if_missing``(p_table VARCHAR(128), p_col VARCHAR(128), p_def TEXT)
BEGIN
  IF NOT EXISTS (SELECT 1 FROM information_schema.COLUMNS
                 WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = p_table AND COLUMN_NAME = p_col) THEN
    SET @p_add_col_sql = CONCAT('ALTER TABLE ``', p_table, '`` ADD COLUMN ', p_def);
    PREPARE stmt FROM @p_add_col_sql;
    EXECUTE stmt;
    DEALLOCATE PREPARE stmt;
  END IF;
END`$
`$
DELIMITER ;

-- ---------- 第 1 部分：缺失表整表创建 ----------
"@

    $part2 = @"

-- ---------- 第 2 部分：已存在表逐列补字段（不存在才添加） ----------
$($calls -join "`n")

DROP PROCEDURE IF EXISTS ``p_add_col_if_missing``;
SET FOREIGN_KEY_CHECKS=1;
"@

    [IO.File]::WriteAllText($outFile, ($header + "`n" + $dump + $part2), (New-Object System.Text.UTF8Encoding($false)))
    $tableCount = ([regex]::Matches($dump, 'CREATE TABLE IF NOT EXISTS')).Count
    $callCount = ($calls | Measure-Object -Line).Lines
    Write-Output "OK -> $outFile"
    Write-Output "tables=$tableCount columns=$callCount bytes=$((Get-Item $outFile).Length)"
} finally {
    $env:MYSQL_PWD = $prevPwd
}
