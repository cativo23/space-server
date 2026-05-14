<?php
$config['plugins'] = [];
$config['imap_host'] = 'mail:143';
$config['smtp_host'] = 'mail:587';
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
