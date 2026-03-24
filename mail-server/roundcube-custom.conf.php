<?php
// Custom Roundcube configuration for docker-mailserver
// Use plain IMAP/SMTP - SSL only for web (handled by Traefik)

$config['imap_host'] = 'mail:143';
$config['smtp_host'] = 'mail:587';
$config['imap_conn_options'] = null;
$config['smtp_conn_options'] = null;
