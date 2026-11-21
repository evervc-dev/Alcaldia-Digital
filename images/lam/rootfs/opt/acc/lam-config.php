<?php
// Fusiona el perfil AD versionado con lam.conf y pone las contraseñas (desde /etc/acc/lam.env) con el formato SSHA de LAM.
$C = '/var/lib/ldap-account-manager/config';
$env = parse_ini_file('/etc/acc/lam.env');
$ssha = function ($p) { $salt = random_bytes(4); return '{SSHA}' . base64_encode(sha1($p . $salt, true)) . ' ' . base64_encode($salt); };
$prof = json_decode(file_get_contents("$C/lam.conf"), true);
$new = json_decode(file_get_contents('/etc/acc/lam-perfil.json'), true);
foreach ($new as $k => $v) { $prof[$k] = $v; }
$prof['loginSearchPassword'] = $env['SVC_LDAP_PASS'];
$prof['Passwd'] = $ssha($env['LAM_MASTER_PASS']);
file_put_contents("$C/lam.conf", json_encode($prof, JSON_PRETTY_PRINT | JSON_UNESCAPED_SLASHES));
$cfg = json_decode(file_get_contents("$C/config.cfg"), true);
$cfg['password'] = $ssha($env['LAM_MASTER_PASS']);
$cfg['default'] = 'lam';
file_put_contents("$C/config.cfg", json_encode($cfg, JSON_PRETTY_PRINT | JSON_UNESCAPED_SLASHES));
