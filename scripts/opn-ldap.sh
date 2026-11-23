#!/bin/bash
# Login de la GUI de OPNsense con el AD (LDAPS, CA del laboratorio). rol-admin: todo; rol-ti: reglas, alias, IDS, estado y registros (sin usuarios,
# copias de configuración, claves IPsec, reinicio ni captura de paquetes). Soporte y empleados NO entran (filtro LDAP).
# La base local (root) sigue valiendo: rescate si cae el AD. SSH no cambia (solo clave). Idempotente. Uso: opn-ldap.sh <fw-a1|fw-a2|fw-b>
set -euo pipefail; cd "$(dirname "$0")/.."; set -a; . ./.env; set +a; FW=${1:?fw}
case $FW in fw-b) D1=10.20.20.10; D2=10.10.20.10 ;; *) D1=10.10.20.10; D2=10.20.20.10 ;; esac
{ echo "umask 077; cat > /root/acc-ldap.php <<'FIN_PHP'"
cat <<'PHP'
<?php
require_once('script/load_phalcon.php'); use OPNsense\Core\Config;
$in = json_decode(file_get_contents('/root/acc-ldap.json'), true); unlink('/root/acc-ldap.json');
function guardar($m, $l) { foreach ($m->performValidation() as $x) { fwrite(STDERR, "[$l] {$x->getField()}: {$x->getMessage()}\n"); exit(2); } $m->serializeToConfig(false, true); Config::getInstance()->save(); echo "ok: $l\n"; }
$ca = new \OPNsense\Trust\Ca(); $n = null;
foreach ($ca->ca->iterateItems() as $c) { if ((string)$c->descr === 'ACC CA laboratorio') { $n = $c; } }
if (!$n) { $n = $ca->ca->Add(); $n->descr = 'ACC CA laboratorio'; $n->crt = base64_encode($in['ca']); guardar($ca, 'ca'); }
$g = new \OPNsense\Auth\Group(); $have = [];
foreach ($g->group->iterateItems() as $x) { $have[(string)$x->name] = $x; }
$ti = ['page-system-login-logout','page-system-status','page-firewall-rules','page-firewall-rules-edit','page-filter-api','page-firewall-aliases','page-firewall-alias-edit','page-services-ids','page-diagnostics-logs-firewall-dynamic','page-diagnostics-logs-firewall-plain','page-diagnostics-logs-firewall-summary','page-diagnostics-logs-firewall-general','page-diagnostics-logs-system','page-diagnostics-logs-gateways','page-diagnostics-ping','page-diagnostics-traceroute','page-diagnostics-testport','page-diagnostics-arptable','page-diagnostics-routingtables','page-diagnostics-tables','page-diagnostics-showstates','page-diagnostics-system-activity','page-diagnostics-system-pftop','page-status-carp','page-status-interfaces','page-status-ipsec','page-status-ipsec-sad','page-status-services','page-status-systemlogs-ipsecvpn','page-status-systemlogs-routing','page-status-trafficgraph','page-system-gateways'];
foreach (['rol-admin' => ['page-all'], 'rol-ti' => $ti] as $nm => $pv) { $x = $have[$nm] ?? $g->group->Add(); $x->name = $nm; $x->description = "AD: $nm"; $x->priv = implode(',', $pv); }
guardar($g, 'grupos');
$cfg = Config::getInstance()->object(); $b = 'DC=ad,DC=alcaldia,DC=lab'; $viejos = [];
foreach ($cfg->system->authserver as $a) { if (strpos((string)$a->name, 'AD ') === 0) { $viejos[] = $a; } }
foreach ($viejos as $a) { unset($a[0]); }
foreach ($in['dc'] as $i => $ip) { $a = $cfg->system->addChild('authserver');
  foreach (['refid' => 'accldap' . $i, 'type' => 'ldap', 'name' => "AD " . ($i + 1), 'host' => $ip, 'ldap_port' => '636', 'ldap_urltype' => 'SSL - Encrypted', 'ldap_protver' => '3', 'ldap_scope' => 'subtree',
    'ldap_basedn' => $b, 'ldap_authcn' => $b, 'ldap_attr_user' => 'sAMAccountName', 'ldap_binddn' => 'svc-lectura@ad.alcaldia.lab', 'ldap_bindpw' => $in['pw'], 'ldap_attr_memberof' => 'memberOf',
    'ldap_extended_query' => "|(memberOf=CN=rol-admin,CN=Users,$b)(memberOf=CN=rol-ti,CN=Users,$b)", 'ldap_read_properties' => '1', 'ldap_sync_memberof' => '1', 'ldap_sync_memberof_groups' => 'rol-admin,rol-ti',
    'ldap_sync_create_local_users' => '1', 'caseInSensitiveUsernames' => '1'] as $k => $v) { $a->addChild($k, htmlspecialchars($v)); } }
unset($cfg->system->webgui->authmode); $cfg->system->webgui->addChild('authmode', 'Local Database,AD 1,AD 2');
Config::getInstance()->save(); echo "ok: servidores AD\n";
PHP
echo "FIN_PHP"; echo "cat > /root/acc-ldap.json <<'FIN_JSON'"; python3 -c 'import json,os,sys;print(json.dumps({"ca":open("config/pki/ca.crt").read(),"pw":os.environ["SVC_LDAP_PASS"],"dc":sys.argv[1:]}))' $D1 $D2; echo FIN_JSON
echo 'cp /conf/config.xml /conf/backup/config-antes-ldap.xml; cd /usr/local/opnsense/mvc && php /root/acc-ldap.php; rc=$?; rm -f /root/acc-ldap.php /root/acc-ldap.json; configctl system trust configure >/dev/null 2>&1 || true; [ -x /usr/sbin/certctl ] && certctl rehash >/dev/null 2>&1; configctl webgui restart >/dev/null 2>&1; exit $rc'; } | bash scripts/fw.sh "$FW" - 2>&1 | grep -v SO_RCV
