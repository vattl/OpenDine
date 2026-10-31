/*
 Navicat Premium Dump SQL

 Source Server         : localhost
 Source Server Type    : MySQL
 Source Server Version : 80042 (8.0.42)
 Source Host           : localhost:3306
 Source Schema         : db_diancan

 Target Server Type    : MySQL
 Target Server Version : 80042 (8.0.42)
 File Encoding         : 65001

 Date: 27/04/2026 03:01:23
*/

SET NAMES utf8mb4;
SET FOREIGN_KEY_CHECKS = 0;

-- ----------------------------
-- Table structure for t_queue_ticket
-- ----------------------------
DROP TABLE IF EXISTS `t_queue_ticket`;
CREATE TABLE `t_queue_ticket`  (
  `id` bigint NOT NULL AUTO_INCREMENT,
  `ticket_no` varchar(32) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci NOT NULL COMMENT '排队号，如 A102',
  `shop_id` int NOT NULL DEFAULT 1 COMMENT '门店ID，连锁按门店隔离',
  `openid` varchar(100) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci NOT NULL COMMENT '用户 openid',
  `mobile` varchar(20) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci NOT NULL COMMENT '手机号',
  `party_size` int NOT NULL COMMENT '就餐人数',
  `dine_type` varchar(32) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci NOT NULL COMMENT '就餐方式，如 dinein',
  `remark` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci NULL DEFAULT NULL COMMENT '备注',
  `status` enum('waiting','calling','seated','cancelled','expired') CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci NOT NULL DEFAULT 'waiting' COMMENT '排队状态',
  `created_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`) USING BTREE,
  UNIQUE INDEX `uk_shop_ticket_no`(`shop_id` ASC, `ticket_no` ASC) USING BTREE,
  INDEX `idx_shop_status_created`(`shop_id` ASC, `status` ASC, `created_at` ASC) USING BTREE,
  INDEX `idx_openid_created`(`openid` ASC, `created_at` ASC) USING BTREE
) ENGINE = InnoDB CHARACTER SET = utf8mb4 COLLATE = utf8mb4_general_ci COMMENT = '排队取号记录' ROW_FORMAT = Dynamic;

SET FOREIGN_KEY_CHECKS = 1;
