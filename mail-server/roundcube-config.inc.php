<?php
// Roundcube config for docker-mailserver
// Traefik handles SSL for web, internal traffic is plain
$config['plugins'] = [];
$config['imap_host'] = 'mail:143';
$config['smtp_host'] = 'mail:587';
$config['smtp_port'] = 587;
$config['smtp_user'] = '%u';
$config['smtp_pass'] = '%p';
$config['db_dsnw'] = 'sqlite:////var/roundcube/db/db.sqlite';
$config['skin'] = 'elastic';
