<?php
/* Instala el hash de /root/root.hash como contraseña de root (GUI, consola y SSH) y borra el archivo.
 * El hash se genera en el host con scripts/opnsense-root-hash.sh (desde .env); el texto plano nunca llega aquí. */
require_once('config.inc');
require_once('auth.inc');
$hash = trim(@file_get_contents('/root/root.hash'));
@unlink('/root/root.hash');
if (strpos($hash, '$6$') !== 0) { fwrite(STDERR, "hash inválido\n"); exit(1); }
global $config;
foreach ($config['system']['user'] as &$u) {
    if ($u['name'] === 'root') { $u['password'] = $hash; local_user_set($u); break; }
}
write_config('ACC: contraseña de root desde .env');
echo "contraseña de root actualizada\n";
