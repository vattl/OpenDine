/*
 Navicat Premium Dump SQL

 Source Server         : db_diancan
 Source Server Type    : MySQL
 Source Server Version : 80042 (8.0.42)
 Source Host           : 127.0.0.1:3306
 Source Schema         : db_diancan

 Target Server Type    : MySQL
 Target Server Version : 80042 (8.0.42)
 File Encoding         : 65001

 Date: 04/08/2026 16:21:38
*/

SET NAMES utf8mb4;
SET FOREIGN_KEY_CHECKS = 0;

-- ----------------------------
-- Table structure for t_order_client_request
-- ----------------------------
DROP TABLE IF EXISTS `t_order_client_request`;
CREATE TABLE `t_order_client_request`  (
  `id` bigint NOT NULL AUTO_INCREMENT,
  `shop_id` int NOT NULL,
  `admin_id` int NULL DEFAULT NULL,
  `client_request_id` varchar(128) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci NOT NULL,
  `request_path` varchar(128) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci NOT NULL,
  `request_fingerprint` char(64) CHARACTER SET ascii COLLATE ascii_general_ci NULL COMMENT '规范化请求体 SHA-256',
  `status` varchar(16) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci NOT NULL DEFAULT 'PROCESSING',
  `response_snapshot` longtext CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci NULL,
  `expires_at` datetime NOT NULL,
  `created_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`) USING BTREE,
  UNIQUE INDEX `uk_order_client_request`(`shop_id` ASC, `client_request_id` ASC) USING BTREE,
  INDEX `idx_order_client_request_expiry`(`expires_at` ASC) USING BTREE
) ENGINE = InnoDB CHARACTER SET = utf8mb4 COLLATE = utf8mb4_general_ci COMMENT = '收银APP写请求24小时幂等账本' ROW_FORMAT = Dynamic;

SET FOREIGN_KEY_CHECKS = 1;
