<?php
/* Añade /root/acc_admin.pub a las claves autorizadas de root (OPNsense guarda authorizedkeys en base64). */
require_once('config.inc');
require_once('auth.inc');
$pub = trim(@file_get_contents('/root/acc_admin.pub'));
if (strpos($pub, 'ssh-ed25519 ') !== 0) { fwrite(STDERR, "clave inválida\n"); exit(1); }
global $config;
foreach ($config['system']['user'] as &$u) {
    if ($u['name'] === 'root') {
        $keys = isset($u['authorizedkeys']) ? base64_decode($u['authorizedkeys']) : '';
        if (strpos($keys, $pub) === false) { $keys = trim($keys . "\n" . $pub); }
        $u['authorizedkeys'] = base64_encode($keys);
        local_user_set($u);
        break;
    }
}
write_config('ACC: clave SSH de administración');
echo "clave SSH de root instalada\n";
