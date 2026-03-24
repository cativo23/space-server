<?php
// Roundcube Docker config - plain IMAP/SMTP for internal Docker network
// SSL/TLS only for web interface (handled by Traefik)

$config['imap_host'] = 'mail:143';
$config['smtp_host'] = 'mail:587';
$config['smtp_port'] = 587;
$config['imap_conn_options'] = null;
$config['smtp_conn_options'] = null;
$config['db_dsnw'] = 'sqlite:////var/roundcube/db/db.sqlite';
$config['db_dsnr'] = 'sqlite:////var/roundcube/db/db.sqlite';
$config['temp_dir'] = '/tmp/';
$config['skin'] = 'elastic';
