SET FOREIGN_KEY_CHECKS = 0;

CREATE TABLE IF NOT EXISTS `flex_brickphone_groups` (
    `id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    `name` VARCHAR(100) NOT NULL,
    `owner_identifier` VARCHAR(128) NOT NULL,
    `owner_name` VARCHAR(100) NOT NULL,
    `status` VARCHAR(20) NOT NULL DEFAULT 'active',
    `avatar` VARCHAR(255) DEFAULT NULL,
    `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    `updated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (`id`),
    INDEX `idx_owner` (`owner_identifier`),
    INDEX `idx_status` (`status`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `flex_brickphone_group_members` (
    `group_id` BIGINT UNSIGNED NOT NULL,
    `identifier` VARCHAR(128) NOT NULL,
    `name` VARCHAR(100) NOT NULL,
    `role` VARCHAR(20) NOT NULL DEFAULT 'member',
    `joined_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (`group_id`, `identifier`),
    INDEX `idx_identifier` (`identifier`),
    CONSTRAINT `fk_members_group` FOREIGN KEY (`group_id`) 
        REFERENCES `flex_brickphone_groups` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `flex_brickphone_group_messages` (
    `id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    `group_id` BIGINT UNSIGNED NOT NULL,
    `sender_identifier` VARCHAR(128) NOT NULL,
    `sender_name` VARCHAR(100) NOT NULL,
    `message_type` VARCHAR(30) NOT NULL DEFAULT 'text',
    `message` TEXT NOT NULL,
    `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (`id`),
    INDEX `idx_group_message` (`group_id`, `id`),
    CONSTRAINT `fk_messages_group` FOREIGN KEY (`group_id`) 
        REFERENCES `flex_brickphone_groups` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `flex_brickphone_group_invites` (
    `id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    `group_id` BIGINT UNSIGNED NOT NULL,
    `target_identifier` VARCHAR(128) NOT NULL,
    `inviter_identifier` VARCHAR(128) NOT NULL,
    `inviter_name` VARCHAR(100) NOT NULL,
    `expires_at` DATETIME NOT NULL,
    `status` VARCHAR(20) NOT NULL DEFAULT 'pending',
    `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (`id`),
    UNIQUE KEY `uq_group_invite` (`group_id`, `target_identifier`),
    INDEX `idx_invite_target` (`target_identifier`, `status`),
    CONSTRAINT `fk_invites_group` FOREIGN KEY (`group_id`) 
        REFERENCES `flex_brickphone_groups` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `flex_brickphone_group_contacts` (
    `id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    `group_id` BIGINT UNSIGNED NOT NULL,
    `contact_id` VARCHAR(100) NOT NULL,
    `display_name` VARCHAR(100) NOT NULL,
    `contact_type` VARCHAR(50) NOT NULL DEFAULT 'contact',
    `phone_identifier` VARCHAR(100) DEFAULT NULL,
    `permissions` VARCHAR(1000) DEFAULT NULL,
    `created_by` VARCHAR(128) NOT NULL,
    `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (`id`),
    UNIQUE KEY `uq_group_contact` (`group_id`, `contact_id`),
    CONSTRAINT `fk_contacts_group` FOREIGN KEY (`group_id`) 
        REFERENCES `flex_brickphone_groups` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

SET FOREIGN_KEY_CHECKS = 1;