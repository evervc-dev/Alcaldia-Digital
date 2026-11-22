<?php
/*
 * Configuración del Site B (Tier I, sitio tibio) para OPNsense 26.7 — fw-b (sin HA).
 * Uso (en el firewall):  php /root/site-b.php b    y luego reiniciar.
 * Usa los modelos MVC de OPNsense (validan cada campo) + secciones legacy (interfaces, system).
 * Fuente de direcciones: inventory/ipam.md
 */
require_once('script/load_phalcon.php');
use OPNsense\Core\Config;
require_once(__DIR__ . '/wan-ab.inc.php');
require_once(__DIR__ . '/dhcp.inc.php');

$role = 'b';
$VLANS = [ // tag => [ifname, descr]   (Site B no tiene VLAN 50 USUARIOS)
    10 => ['lan',  'GESTION'],
    20 => ['opt2', 'SERVIDORES'],
    30 => ['opt3', 'DMZ'],
    40 => ['opt4', 'ADMINISTRACION'],
    60 => ['opt6', 'RESPALDO'],
];

$cfg = Config::getInstance()->object();

/* ---------- system ---------- */
$cfg->system->hostname = "fw-{$role}";
$cfg->system->domain = 'site-b.alcaldia.lab';
$cfg->system->timezone = 'America/El_Salvador';
unset($cfg->system->dnsserver);
$cfg->system->addChild('dnsserver', '1.1.1.1');
$cfg->system->addChild('dnsserver', '8.8.8.8');
$cfg->system->gw_switch_default = '1';               // conmuta la ruta por defecto si cae WAN1
if (!isset($cfg->system->ssh)) { $cfg->system->addChild('ssh'); }
$cfg->system->ssh->enabled = 'enabled';
$cfg->system->ssh->permitrootlogin = '1';
$cfg->system->ssh->passwordauth = '1';
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
$add_if('wan',  'vtnet0', 'WAN1',  '203.0.113.10', '30', 'WAN1_GW');
$add_if('opt1', 'vtnet1', 'WAN2',  '198.51.100.10', '30', 'WAN2_GW');
foreach ($VLANS as $tag => [$ifn, $descr]) {
    $add_if($ifn, "vlan0.$tag", $descr, "10.20.$tag.1", '24');
}
wan_ab_interfaces($ifs);
sede_interfaces($ifs, 'b');

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

/* ---------- Sin CARP en el Site B (Tier I) ---------- */
$vip = new \OPNsense\Interfaces\Vip();
reset_array($vip->vip);
save_model($vip, 'vip (vacío)');

/* ---------- Gateways + grupo de failover ---------- */
$gw = new \OPNsense\Routing\Gateways();
reset_array($gw->gateway_item);
$gw->gateway_item->Add()->setNodes(['name' => 'WAN1_GW', 'descr' => 'ISP1', 'interface' => 'wan',
    'ipprotocol' => 'inet', 'gateway' => '203.0.113.9', 'defaultgw' => '1', 'priority' => '10', 'weight' => '1',
    'monitor_disable' => '0', 'monitor_killstates' => '1', 'monitor' => '203.0.113.9', 'interval' => '1', 'time_period' => '10', 'loss_interval' => '2']);
$gw->gateway_item->Add()->setNodes(['name' => 'WAN2_GW', 'descr' => 'ISP2', 'interface' => 'opt1',
    'ipprotocol' => 'inet', 'gateway' => '198.51.100.9', 'defaultgw' => '1', 'priority' => '20', 'weight' => '1',
    'monitor_disable' => '0', 'monitor_killstates' => '1', 'monitor' => '198.51.100.9', 'interval' => '1', 'time_period' => '10', 'loss_interval' => '2']);
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
$want = ['PUERTOS_PUBLICADOS' => "80\n443\n8000\n8080\n9091\n9200", 'PUERTOS_WEB_DNS' => "53\n80\n443", 'PUERTOS_IKE' => "500\n4500", 'PUERTOS_AD' => "53\n88\n389\n636", 'PUERTOS_RDP' => "3389", 'PUERTOS_SEDE' => "53\n3389"];
foreach ($al->aliases->alias->iterateItems() as $uuid => $a) {
    if (isset($want[(string)$a->name])) { $al->aliases->alias->del($uuid); }
}
foreach ($want as $name => $content) {
    $al->aliases->alias->Add()->setNodes(['enabled' => '1', 'name' => $name, 'type' => 'port',
        'content' => $content, 'description' => 'ACC Site B']);
}
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
$rule('opt4', 'pass', 'ADMIN: acceso total (personal del centro)', ['log' => '0']);
$rule('lan',  'block', 'GESTION -> ADMIN bloqueado', ['destination_net' => 'opt4']);
$rule('lan',  'pass', 'GESTION: gestión, NTP y actualizaciones', ['log' => '0']);
$rule('opt2', 'pass', 'SERVIDORES -> GESTION (syslog/SNMP traps)', ['destination_net' => 'lan']);
$rule('opt2', 'pass', 'SERVIDORES -> Internet (actualizaciones)', ['destination_net' => '10.0.0.0/8', 'destination_not' => '1', 'log' => '0']);
$rule('opt2', 'pass', 'SERVIDORES -> otro sitio (réplicas)', ['destination_net' => '10.10.0.0/16', 'log' => '0']);
$rule('opt2', 'block', 'SERVIDORES: resto bloqueado');
wan_ab_rules($rule, 'b');
$rule('opt3', 'pass', 'DMZ -> servicios publicados', ['destination_net' => 'opt2', 'protocol' => 'TCP', 'destination_port' => 'PUERTOS_PUBLICADOS']);
$rule('opt3', 'pass', 'DMZ -> DNS interno', ['destination_net' => 'opt2', 'protocol' => 'TCP/UDP', 'destination_port' => '53']);
$rule('opt3', 'pass', 'DMZ -> Internet (cloudflared)', ['destination_net' => '10.0.0.0/8', 'destination_not' => '1', 'log' => '0']);
$rule('opt3', 'block', 'DMZ: resto bloqueado');
$rule('opt6', 'pass', 'RESPALDO -> DC local (LDAP/Kerberos/DNS para el NAS)', ['destination_net' => 'opt2', 'protocol' => 'TCP/UDP', 'destination_port' => 'PUERTOS_AD', 'log' => '0']);
$rule('opt6', 'pass', 'RESPALDO -> Internet/Site A', ['destination_net' => '10.20.0.0/16', 'destination_not' => '1', 'log' => '0']);
$rule('opt6', 'block', 'RESPALDO: resto bloqueado');
// NAT de salida hacia la VIP CARP de cada WAN (las sesiones sobreviven al failover)
$snat = 10;
foreach ([['wan', '203.0.113.10'], ['opt1', '198.51.100.10']] as [$ifn, $vipip]) {
    $f->snatrules->rule->Add()->setNodes(['enabled' => '1', 'interface' => $ifn, 'ipprotocol' => 'inet',
        'protocol' => 'any', 'source_net' => '10.0.0.0/8', 'destination_net' => 'any', 'target' => $vipip,
        'sequence' => (string)$snat, 'description' => "Salida a Internet por $vipip"]);
    $snat += 10;
}
if (isset($f->general->snat_mode)) { $f->general->snat_mode = 'hybrid'; }
save_model($f, 'filtro+nat');
Config::getInstance()->save();
$cfg = Config::getInstance()->object();
if (!isset($cfg->nat->outbound)) { $cfg->nat->addChild('outbound'); }
$cfg->nat->outbound->mode = 'hybrid';

/* ---------- DHCP (RQ-13) ---------- */
dhcp_apply(['opt4' => ['10.20.40', 100, 199]]);

/* ---------- WAN A<->B (IPsec VTI + OSPF) ---------- */
wan_ab_apply('b', '10.20.10.1', ['lan', 'opt2', 'opt3', 'opt4', 'opt6']);

Config::getInstance()->save();
echo "Configuración de fw-$role guardada. Aplicar: reiniciar (/usr/local/etc/rc.reboot) o 'pluginctl -s dpinger restart' si solo cambian gateways\n";
