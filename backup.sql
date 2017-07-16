CREATE DATABASE IF NOT EXISTS `backup` DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci;
USE `backup`;

DROP TABLE IF EXISTS `options`;
CREATE TABLE `options` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `name` varchar(64) NOT NULL,
  `value` varchar(512) NOT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `name` (`name`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

LOCK TABLES `options` WRITE;
INSERT INTO `options` VALUES (NULL,'default_backup_host','localhost'),(NULL,'default_backup_path','/mnt/backup/machines/'),(NULL,'default_backup_port','3455'),(NULL,'default_backup_rsync','/usr/bin/rsync'),(NULL,'default_backup_ssh','/usr/bin/ssh'),(NULL,'default_backup_user','root'),(NULL,'default_src_port','22'),(NULL,'default_src_user','root'),(NULL,'rsync_excludes','\"/dev/*\",\"/proc/*\",\"/sys/*\",\"/tmp/*\",\"/run/*\",\"/mnt/*\",\"/media/*\",\"/lost+found\"'),(NULL,'rsync_opt','-abAHX'),(NULL,'ssh_path','/usr/bin/ssh'),(NULL,'incr_limit','3'),(NULL,'sshagent_path','/usr/bin/ssh-agent'),(NULL,'sshkey_path','/root/.ssh/id_rsa'),(NULL,'log_directory','/root/backup_log/id_rsa');
UNLOCK TABLES;

DROP TABLE IF EXISTS `dbs`;
CREATE TABLE `dbs` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `type` varchar(32) NOT NULL,
  `hostid` int(11) NOT NULL,
  `name` varchar(128) NOT NULL,
  `username` varchar(128) NOT NULL,
  `password` varchar(128) NOT NULL,
  PRIMARY KEY (`id`),
  KEY `hostid` (`hostid`),
  CONSTRAINT `dbs_ibfk_1` FOREIGN KEY (`hostid`) REFERENCES `hosts` (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

DROP TABLE IF EXISTS `hosts`;
CREATE TABLE `hosts` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `name` varchar(64) NOT NULL,
  `src_host` varchar(64) NOT NULL,
  `src_user` varchar(64) NOT NULL,
  `src_port` varchar(64) NOT NULL,
  `dst_host` varchar(64) NOT NULL,
  `dst_port` varchar(64) NOT NULL,
  `dst_user` varchar(64) NOT NULL,
  `dst_path` varchar(256) NOT NULL,
  `dst_rsync` varchar(256) NOT NULL,
  `dst_ssh` varchar(256) NOT NULL,
  `rsync_excludes` varchar(256) NOT NULL,
  PRIMARY KEY (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

DROP TABLE IF EXISTS `tasks`;
CREATE TABLE `tasks` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `hostid` int(11) NOT NULL,
  `backup_type` varchar(32) NOT NULL,
  `date_created` datetime NOT NULL,
  `date_start` datetime NOT NULL,
  `date_stop` datetime NOT NULL,
  `status` varchar(32) NOT NULL,
  PRIMARY KEY (`id`),
  KEY `hostid` (`hostid`),
  CONSTRAINT `tasks_ibfk_1` FOREIGN KEY (`hostid`) REFERENCES `hosts` (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
