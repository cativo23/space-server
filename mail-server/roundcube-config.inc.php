<?php
// Roundcube configuration for docker-mailserver (space-server stack).
// IMAP and SMTP use STARTTLS to the internal Docker container; peer
// verification is disabled because docker-mailserver uses a self-signed cert.

$config['plugins'] = [];
$config['imap_host'] = 'tls://mail:143';
$config['smtp_host'] = 'tls://mail:587';
$config['smtp_port'] = 587;
$config['smtp_user'] = '%u';
$config['smtp_pass'] = '%p';
$config['smtp_auth_type'] = 'PLAIN';
$config['smtp_use_tls'] = true;
$config['smtp_tls_wrapper'] = false;
$config['db_dsnw'] = 'sqlite:////var/roundcube/db/db.sqlite';
$config['skin'] = 'elastic';
$config['imap_conn_options']['ssl']['verify_peer'] = false;
$config['imap_conn_options']['ssl']['verify_peer_name'] = false;
$config['smtp_conn_options']['ssl']['verify_peer'] = false;
$config['smtp_conn_options']['ssl']['verify_peer_name'] = false;

// Include Docker-generated config (driven by ROUNDCUBEMAIL_* env vars).
// This must be last so env-var overrides take effect after our defaults.
include(__DIR__ . '/config.docker.inc.php');
