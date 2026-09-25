-- Savings accounts (one per character, keyed by citizenid) and gang accounts (keyed by gangid).
-- Balances are projections of w_centralbank accounts.
CREATE TABLE IF NOT EXISTS `bank_accounts` (
  `record_id` bigint(255) NOT NULL AUTO_INCREMENT,
  `citizenid` varchar(250) DEFAULT NULL,
  `gangid` varchar(50) DEFAULT NULL,
  `amount` decimal(18,2) NOT NULL DEFAULT 0,
  `account_type` enum('Savings','Gang') NOT NULL DEFAULT 'Savings',
  PRIMARY KEY (`record_id`),
  UNIQUE KEY `citizenid` (`citizenid`),
  KEY `gangid` (`gangid`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

CREATE TABLE IF NOT EXISTS `bank_statements` (
  `record_id` bigint(255) NOT NULL AUTO_INCREMENT,
  `citizenid` varchar(50) DEFAULT NULL,
  `account` varchar(50) DEFAULT NULL,
  `gangid` varchar(50) DEFAULT NULL,
  `deposited` decimal(18,2) DEFAULT NULL,
  `withdraw` decimal(18,2) DEFAULT NULL,
  `balance` decimal(18,2) DEFAULT NULL,
  `date` varchar(50) DEFAULT NULL,
  `type` varchar(255) DEFAULT NULL,
  `request_key` varchar(190) DEFAULT NULL,
  PRIMARY KEY (`record_id`),
  UNIQUE KEY `cb_request_key` (`request_key`),
  KEY `citizenid` (`citizenid`),
  KEY `gangid` (`gangid`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
