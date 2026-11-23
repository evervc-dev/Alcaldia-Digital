<?php
/*
 * Configuración del Site A (Tier II) para OPNsense 26.7 — fw-a1 / fw-a2 en CARP.
 * Uso (en el firewall):  php /root/site-a.php a1|a2    y luego reiniciar.
 * Usa los modelos MVC de OPNsense (validan cada campo) + secciones legacy (interfaces, system).
 * Fuente de direcciones: inventory/ipam.md
 */
require_once('script/load_phalcon.php');
use OPNsense\Core\Config;
require_once(__DIR__ . '/wan-ab.inc.php');
require_once(__DIR__ . '/dhcp.inc.php');

$role = $argv[1] ?? '';
if (!in_array($role, ['a1', 'a2'])) { fwrite(STDERR, "uso: php site-a.php a1|a2\n"); exit(1); }
$me    = $role === 'a1' ? 2 : 3;          // último octeto propio (.2 / .3)
$skew  = $role === 'a1' ? 0 : 100;        // a1 = MASTER preferido
$peer99 = $role === 'a1' ? '10.10.99.2' : '10.10.99.1';
$my99   = $role === 'a1' ? '10.10.99.1' : '10.10.99.2';
$CARP_PASS = 'acc-carp-lab';              // laboratorio; no es un secreto real

$VLANS = [ // tag => [ifname, descr]
    10 => ['lan',  'GESTION'],
    20 => ['opt2', 'SERVIDORES'],
    30 => ['opt3', 'DMZ'],
    40 => ['opt4', 'ADMINISTRACION'],
    50 => ['opt5', 'USUARIOS'],
    60 => ['opt6', 'RESPALDO'],
];

$cfg = Config::getInstance()->object();

/* ---------- system ---------- */
$cfg->system->hostname = "fw-{$role}";
$cfg->system->domain = 'site-a.alcaldia.lab';
$cfg->system->timezone = 'America/El_Salvador';
unset($cfg->system->dnsserver);
$cfg->system->addChild('dnsserver', '1.1.1.1');
$cfg->system->addChild('dnsserver', '8.8.8.8');
$cfg->system->gw_switch_default = '1';               // conmuta la ruta por defecto si cae WAN1
if (!isset($cfg->system->ssh)) { $cfg->system->addChild('ssh'); }
$cfg->system->ssh->enabled = 'enabled';
$cfg->system->ssh->permitrootlogin = '1';
$cfg->system->ssh->passwordauth = '0';               // T5 (F10): solo clave (la administración usa la clave de adm-pc)
$cfg->system->ssh->interfaces = 'lan,opt4';          // T5: SSH solo en GESTION y ADMIN
if (!isset($cfg->system->webgui)) { $cfg->system->addChild('webgui'); }
$cfg->system->webgui->interfaces = 'lan,opt4';       // T5: GUI solo en GESTION y ADMIN
unset($cfg->trigger_initial_wizard);

/* ---------- interfaces (legacy) ---------- */
unset($cfg->interfaces);
$ifs = $cfg->addChild('interfaces');
$add_if = function ($name, $dev, $descr, $ip, $bits, $gw = null) use ($ifs) {
    $n = $ifs->addChild($name);
    $n->addChild('if', $dev);
    $n->addChild('descr', $descr);
    $n->addChild('enable', '1');
    $n->addChild('ipaddr', $ip);
    $n->addChild('subnet', $bits);
    if ($gw) { $n->addChild('gateway', $gw); }
};
$add_if('wan',  'vtnet0', 'WAN1',  "203.0.113.$me", '29', 'WAN1_GW');
$add_if('opt1', 'vtnet1', 'WAN2',  "198.51.100.$me", '29', 'WAN2_GW');
foreach ($VLANS as $tag => [$ifn, $descr]) {
    $add_if($ifn, "vlan0.$tag", $descr, "10.10.$tag.$me", '24');
}
$add_if('opt7', 'vtnet3', 'PFSYNC', $my99, '29');
wan_ab_interfaces($ifs);
sede_interfaces($ifs, 'a');

/* ---------- helpers de modelos ---------- */
function reset_array($field) { foreach ($field->iterateItems() as $uuid => $item) { $field->del($uuid); } }
function save_model($mdl, $label) {
    $msgs = $mdl->performValidation();
    if (count($msgs)) {
        foreach ($msgs as $m) { fwrite(STDERR, "[$label] {$m->getField()}: {$m->getMessage()}\n"); }
        exit(2);
    }
    $mdl->serializeToConfig(false, true);
    echo "ok: $label\n";
}

/* ---------- VLAN ---------- */
$vlan = new \OPNsense\Interfaces\Vlan();
reset_array($vlan->vlan);
foreach ($VLANS as $tag => [$ifn, $descr]) {
    $vlan->vlan->Add()->setNodes(['if' => 'vtnet2', 'tag' => (string)$tag, 'pcp' => '0',
        'descr' => $descr, 'vlanif' => "vlan0.$tag"]);
}
save_model($vlan, 'vlans');
Config::getInstance()->save();   // los modelos siguientes validan contra interfaces/VLAN ya guardadas

/* ---------- CARP (Virtual IPs) ---------- */
$vip = new \OPNsense\Interfaces\Vip();
reset_array($vip->vip);
$carp = [['wan', '203.0.113.4', 29, 1, 'VIP WAN1'], ['opt1', '198.51.100.4', 29, 2, 'VIP WAN2']];
foreach ($VLANS as $tag => [$ifn, $descr]) { $carp[] = [$ifn, "10.10.$tag.1", 24, $tag, "VIP $descr"]; }
foreach ($carp as [$ifn, $ip, $bits, $vhid, $descr]) {
    $vip->vip->Add()->setNodes(['interface' => $ifn, 'mode' => 'carp', 'subnet' => $ip,
        'subnet_bits' => (string)$bits, 'vhid' => (string)$vhid, 'advbase' => '1',
        'advskew' => (string)$skew, 'password' => $CARP_PASS, 'descr' => $descr]);
}
save_model($vip, 'carp');

/* ---------- Gateways + grupo de failover ---------- */
$gw = new \OPNsense\Routing\Gateways();
reset_array($gw->gateway_item);
$gw->gateway_item->Add()->setNodes(['name' => 'WAN1_GW', 'descr' => 'ISP1', 'interface' => 'wan',
    'ipprotocol' => 'inet', 'gateway' => '203.0.113.1', 'defaultgw' => '1', 'priority' => '10', 'weight' => '1',
    'monitor_disable' => '0', 'monitor_killstates' => '1', 'monitor' => '203.0.113.1', 'interval' => '1', 'time_period' => '10', 'loss_interval' => '2']);
$gw->gateway_item->Add()->setNodes(['name' => 'WAN2_GW', 'descr' => 'ISP2', 'interface' => 'opt1',
    'ipprotocol' => 'inet', 'gateway' => '198.51.100.1', 'defaultgw' => '1', 'priority' => '20', 'weight' => '1',
    'monitor_disable' => '0', 'monitor_killstates' => '1', 'monitor' => '198.51.100.1', 'interval' => '1', 'time_period' => '10', 'loss_interval' => '2']);
save_model($gw, 'gateways');
Config::getInstance()->save();
// grupo en formato legacy "GW|tier": el propio campo GatewayGroupItemField lo interpreta
$cfg = Config::getInstance()->object();
unset($cfg->gateways->gateway_group);
if (!isset($cfg->gateways)) { $cfg->addChild('gateways'); }
$gg = $cfg->gateways->addChild('gateway_group');
$gg->addChild('name', 'WAN_FAILOVER');
$gg->addChild('item', 'WAN1_GW|1');
$gg->addChild('item', 'WAN2_GW|2');
$gg->addChild('trigger', 'down');
$gg->addChild('descr', 'ISP1 principal, ISP2 respaldo');
Config::getInstance()->save();

/* ---------- Alias de puertos (las reglas no aceptan listas) ---------- */
$al = new \OPNsense\Firewall\Alias();
$want = ['PUERTOS_PUBLICADOS' => "80\n443\n8000\n8080\n9091\n9200", 'PUERTOS_WEB_DNS' => "53\n80\n443", 'PUERTOS_IKE' => "500\n4500", 'PUERTOS_AD' => "53\n88\n389\n636", 'PUERTOS_RDP' => "3389", 'PUERTOS_SEDE' => "53\n3389", 'PUERTOS_AD_CLIENTE' => "53\n88\n123\n135\n389\n445\n464\n636\n3268\n3269\n49152:65535"];
foreach ($al->aliases->alias->iterateItems() as $uuid => $a) {
    if (isset($want[(string)$a->name])) { $al->aliases->alias->del($uuid); }
}
foreach ($want as $name => $content) {
    $al->aliases->alias->Add()->setNodes(['enabled' => '1', 'name' => $name, 'type' => 'port',
        'content' => $content, 'description' => 'ACC Site A']);
}
/* IDS (Suricata): tabla de IPs atacantes que el vigía del IDS llena (respuesta activa, 1 h) -> bloqueada en las WAN */
foreach ($al->aliases->alias->iterateItems() as $uuid => $a) { if ((string)$a->name === 'ACC_IDS_BLOQUEO') { $al->aliases->alias->del($uuid); } }
$al->aliases->alias->Add()->setNodes(['enabled' => '1', 'name' => 'ACC_IDS_BLOQUEO', 'type' => 'external', 'content' => '',
    'description' => 'ACC: IP atacantes detectadas por el IDS (respuesta activa, 1 h)']);
save_model($al, 'alias');
Config::getInstance()->save();

/* ---------- Reglas y NAT de salida ---------- */
$f = new \OPNsense\Firewall\Filter();
reset_array($f->rules->rule);
reset_array($f->snatrules->rule);
$seq = 10;
$rule = function ($ifn, $action, $descr, $extra = []) use ($f, &$seq) {
    $f->rules->rule->Add()->setNodes(array_merge(['enabled' => '1', 'action' => $action, 'quick' => '1',
        'interface' => $ifn, 'direction' => 'in', 'ipprotocol' => 'inet', 'protocol' => 'any',
        'source_net' => 'any', 'destination_net' => 'any', 'log' => '1', 'sequence' => (string)$seq,
        'description' => $descr], $extra));
    $seq += 10;
};
$rule('opt7', 'pass', 'PFSYNC: todo entre nodos HA', ['log' => '0']);
$rule('opt4', 'pass', 'ADMIN: acceso total (personal del centro)', ['log' => '0']);
$rule('lan',  'block', 'GESTION -> ADMIN bloqueado', ['destination_net' => 'opt4']);
$rule('lan',  'pass', 'GESTION: gestión, NTP y actualizaciones', ['log' => '0']);
$rule('opt2', 'pass', 'SERVIDORES -> GESTION (syslog/SNMP traps)', ['destination_net' => 'lan']);
$rule('opt2', 'pass', 'SERVIDORES -> Internet (actualizaciones)', ['destination_net' => '10.0.0.0/8', 'destination_not' => '1', 'log' => '0']);
$rule('opt2', 'pass', 'SERVIDORES -> otro sitio (réplicas)', ['destination_net' => '10.20.0.0/16', 'log' => '0']);
$rule('opt2', 'pass', 'MONITOREO: zbx-server -> todos los equipos (ping, SNMP, puertos de servicio)', ['source_net' => '10.10.20.30/32', 'log' => '0']);
$rule('opt2', 'pass', 'RESPALDO: clientes restic -> NAS (API S3)', ['destination_net' => '10.10.60.10/32', 'protocol' => 'TCP', 'destination_port' => '9000', 'log' => '0']);
$rule('opt2', 'block', 'SERVIDORES: resto bloqueado');
wan_ab_rules($rule, 'a');
$rule('opt3', 'pass', 'DMZ -> servicios publicados', ['destination_net' => 'opt2', 'protocol' => 'TCP', 'destination_port' => 'PUERTOS_PUBLICADOS']);
$rule('opt3', 'pass', 'DMZ -> DNS interno', ['destination_net' => 'opt2', 'protocol' => 'TCP/UDP', 'destination_port' => '53']);
$rule('opt3', 'pass', 'DMZ -> servidores Site B (DNS secundario / DR)', ['destination_net' => '10.20.20.0/24', 'protocol' => 'TCP/UDP', 'destination_port' => 'PUERTOS_PUBLICADOS']);
$rule('opt3', 'pass', 'DMZ -> DNS Site B', ['destination_net' => '10.20.20.0/24', 'protocol' => 'TCP/UDP', 'destination_port' => '53']);
$rule('opt3', 'pass', 'WARP (cloudflared-a) -> escritorios ts1 RDP', ['source_net' => '10.10.30.11/32', 'destination_net' => '10.10.20.40/32', 'protocol' => 'TCP', 'destination_port' => 'PUERTOS_RDP']);
$rule('opt3', 'pass', 'DMZ -> Internet (cloudflared)', ['destination_net' => '10.0.0.0/8', 'destination_not' => '1', 'log' => '0']);
$rule('opt3', 'block', 'DMZ: resto bloqueado');
foreach (['10.10.20.10/32', '10.20.20.10/32'] as $dc) { $rule('opt5', 'pass', "USUARIOS -> AD (puestos unidos al dominio) $dc", ['destination_net' => $dc, 'protocol' => 'TCP/UDP', 'destination_port' => 'PUERTOS_AD_CLIENTE', 'log' => '0']); }
$rule('opt5', 'pass', 'USUARIOS -> escritorios (ts1 RDP)', ['destination_net' => '10.10.20.40/32', 'protocol' => 'TCP', 'destination_port' => 'PUERTOS_RDP']);
$rule('opt5', 'pass', 'USUARIOS -> DNS (la web, por la URL pública con MFA)', ['destination_net' => '10.10.20.10/32', 'protocol' => 'TCP/UDP', 'destination_port' => '53']);
$rule('opt5', 'pass', 'USUARIOS -> DNS secundario (dc2)', ['destination_net' => '10.20.20.10/32', 'protocol' => 'TCP/UDP', 'destination_port' => '53']);
$rule('opt5', 'pass', 'USUARIOS -> Internet', ['destination_net' => '10.0.0.0/8', 'destination_not' => '1', 'log' => '0']);
$rule('opt5', 'block', 'USUARIOS: resto bloqueado');
$rule('opt6', 'pass', 'RESPALDO -> DC local (LDAP/Kerberos/DNS para el NAS)', ['destination_net' => 'opt2', 'protocol' => 'TCP/UDP', 'destination_port' => 'PUERTOS_AD', 'log' => '0']);
$rule('opt6', 'pass', 'RESPALDO -> Internet/Site B', ['destination_net' => '10.10.0.0/16', 'destination_not' => '1', 'log' => '0']);
$rule('opt6', 'block', 'RESPALDO: resto bloqueado');
// NAT de salida hacia la VIP CARP de cada WAN (las sesiones sobreviven al failover)
$snat = 10;
foreach ([['wan', '203.0.113.4'], ['opt1', '198.51.100.4']] as [$ifn, $vipip]) {
    $f->snatrules->rule->Add()->setNodes(['enabled' => '1', 'interface' => $ifn, 'ipprotocol' => 'inet',
        'protocol' => 'any', 'source_net' => '10.0.0.0/8', 'destination_net' => 'any', 'target' => $vipip,
        'sequence' => (string)$snat, 'description' => "Salida a Internet por VIP $vipip"]);
    $snat += 10;
}
if (isset($f->general->snat_mode)) { $f->general->snat_mode = 'hybrid'; }
save_model($f, 'filtro+nat');
Config::getInstance()->save();
$cfg = Config::getInstance()->object();
if (!isset($cfg->nat->outbound)) { $cfg->nat->addChild('outbound'); }
$cfg->nat->outbound->mode = 'hybrid';

/* ---------- WAN A<->B (IPsec VTI + OSPF) ---------- */
wan_ab_apply('a', $my99, ['lan', 'opt2', 'opt3', 'opt4', 'opt5', 'opt6']);

/* ---------- DHCP (RQ-13): rango distinto por nodo CARP ---------- */
[$i0, $i1] = $role === 'a1' ? [100, 149] : [150, 199];
dhcp_apply(['opt4' => ['10.10.40', $i0, $i1], 'opt5' => ['10.10.50', $i0, $i1]]);

/* ---------- HA: pfsync ---------- */
$ha = new \OPNsense\Core\Hasync();
$ha->setNodes(['pfsyncinterface' => 'opt7', 'pfsyncpeerip' => $peer99, 'disablepreempt' => '0']);
save_model($ha, 'hasync');

Config::getInstance()->save();
echo "Configuración de fw-$role guardada. Aplicar: reiniciar (/usr/local/etc/rc.reboot) o 'pluginctl -s dpinger restart' si solo cambian gateways\n";
