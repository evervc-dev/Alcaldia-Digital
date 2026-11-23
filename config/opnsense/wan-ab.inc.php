<?php
/*
 * WAN entre sitios A <-> B: 2 túneles IPsec IKEv2 route-based (VTI) + OSPF (os-frr).
 *   T1 por ISP1: A 203.0.113.4 (VIP CARP)  <-> B 203.0.113.10   reqid 1  ipsec1  172.16.0.1/.2  coste 10
 *   T2 por ISP2: A 198.51.100.4 (VIP CARP) <-> B 198.51.100.10  reqid 2  ipsec2  172.16.0.5/.6  coste 20
 * El Site B INICIA (start_action=start, dpd_action=start); el Site A solo RESPONDE (none). Así el nodo BACKUP del CARP
 * nunca levanta túneles y tras un failover B reconecta contra el nuevo MASTER por DPD.
 * La PSK se lee de /root/ipsec.psk (generada en el host desde .env, no versionada) y se borra.
 * Usado por site-a.php y site-b.php.
 */
use OPNsense\Core\Config;

const WAN_AB_TUNNELS = [
    // reqid, ifname, descr, A_outer, B_outer, A_inner, B_inner, cost
    [1, 'opt8', 'VTI_ISP1', '203.0.113.4',  '203.0.113.10',  '172.16.0.1', '172.16.0.2', 10],
    [2, 'opt9', 'VTI_ISP2', '198.51.100.4', '198.51.100.10', '172.16.0.5', '172.16.0.6', 20],
];

/*
 * Sedes distritales (hub-and-spoke, F6): cada kit INICIA 3 túneles desde detrás del CGNAT de su ISP (NAT-T):
 *   A por WAN1 (coste 10), A por WAN2 (coste 20) y B (coste 100). Identidad del kit: FQDN kit-sede-0N.alcaldia.lab.
 *   Interior: A-WAN1 172.16.N.1/.2 · A-WAN2 172.16.N.5/.6 · B 172.16.N.9/.10.  PSK de sedes: /root/ipsec-sedes.psk.
 */
const SEDES_PUB = [1 => '203.0.113.251', 2 => '198.51.100.252', 3 => '203.0.113.253'];  // IP del pool CGNAT de cada sede
function sede_tunnels($side) {
    $t = [];  // reqid, ifname, descr, local_outer, sede_pub, sede_fqdn, inner_local, inner_sede, cost, wanif
    foreach (SEDES_PUB as $n => $pub) {
        $fq = sprintf('kit-sede-%02d.alcaldia.lab', $n); $s2 = sprintf('%02d', $n);
        if ($side === 'a') {
            $t[] = [10 + $n, 'opt' . (8 + 2 * $n), "SEDE{$s2}_WAN1", '203.0.113.4', $pub, $fq, "172.16.$n.1", "172.16.$n.2", 10, 'wan'];
            $t[] = [20 + $n, 'opt' . (9 + 2 * $n), "SEDE{$s2}_WAN2", '198.51.100.4', $pub, $fq, "172.16.$n.5", "172.16.$n.6", 20, 'opt1'];
        } else {
            $t[] = [30 + $n, 'opt' . (9 + $n), "SEDE{$s2}", '203.0.113.10', $pub, $fq, "172.16.$n.9", "172.16.$n.10", 100, 'wan'];
        }
    }
    return $t;
}

/* Asignación de las interfaces VTI (sin IP: la pone el VTI) */
function wan_ab_interfaces($ifs) {
    foreach (WAN_AB_TUNNELS as [$reqid, $ifn, $descr]) {
        $n = $ifs->addChild($ifn);
        $n->addChild('if', "ipsec$reqid");
        $n->addChild('descr', $descr);
        $n->addChild('enable', '1');
    }
}
function sede_interfaces($ifs, $side) {
    foreach (sede_tunnels($side) as [$reqid, $ifn, $descr]) {
        $n = $ifs->addChild($ifn); $n->addChild('if', "ipsec$reqid"); $n->addChild('descr', $descr); $n->addChild('enable', '1');
    }
}

/* Reglas: todo lo que entra por los túneles entre sitios está permitido (el filtrado fino es por zona) */
function wan_ab_rules($rule, $side) {
    // En 26.x las conexiones swanctl NO generan reglas automáticas en WAN: IKE/NAT-T y ESP explícitos
    $wanif = [1 => 'wan', 2 => 'opt1'];
    foreach ($wanif as $w) {   // IDS: respuesta activa (primeras reglas de cada WAN; las sedes y el otro sitio nunca entran en la tabla)
        $rule($w, 'block', 'IDS: IP atacante bloqueada (respuesta activa, 1 h)', ['source_net' => 'ACC_IDS_BLOQUEO']);
    }
    foreach (WAN_AB_TUNNELS as [$reqid, $ifn, $descr, $ao, $bo]) {
        $peer = $side === 'a' ? $bo : $ao;
        $rule($wanif[$reqid], 'pass', "$descr: IKE/NAT-T desde el par", ['protocol' => 'UDP',
            'source_net' => "$peer/32", 'destination_port' => 'PUERTOS_IKE', 'log' => '0']);
        $rule($wanif[$reqid], 'pass', "$descr: ESP desde el par", ['protocol' => 'ESP',
            'source_net' => "$peer/32", 'log' => '0']);
        $rule($ifn, 'pass', "$descr: tráfico entre sitios y OSPF", ['log' => '0']);
    }
    // (el filtrado en enc0 se desactiva con tunables en wan_ab_apply: se filtra solo en las VTI)
    // --- Sedes: solo DNS (dc1/dc2), RDP (ts1) y ping a los servidores; TODO lo demás (incl. sede<->sede) bloqueado y registrado
    foreach (sede_tunnels($side) as [$reqid, $ifn, $descr, $lo, $pub, , , , , $wanif]) {
        $rule($wanif, 'pass', "$descr: IKE/NAT-T desde la sede", ['protocol' => 'UDP', 'source_net' => "$pub/32", 'destination_port' => 'PUERTOS_IKE', 'log' => '0']);
        $rule($wanif, 'pass', "$descr: ESP desde la sede", ['protocol' => 'ESP', 'source_net' => "$pub/32", 'log' => '0']);
        // T5 (F10): una sede no debe alcanzar SSH/GUI del propio firewall (hallado: sin esta regla SSH respondía)
        $rule($ifn, 'block', "$descr: nada hacia el propio firewall (SSH/GUI)", ['protocol' => 'TCP', 'destination_net' => '(self)']);
        $rule($ifn, 'pass', "$descr: OSPF", ['protocol' => 'OSPF', 'log' => '0']);
        foreach (['10.10.20.10/32', '10.20.20.10/32'] as $dc) {   // puestos unidos al dominio: SOLO hacia dc1/dc2
            $rule($ifn, 'pass', "$descr: cliente AD -> $dc", ['protocol' => 'TCP/UDP', 'destination_net' => $dc, 'destination_port' => 'PUERTOS_AD_CLIENTE', 'log' => '0']);
        }
        foreach (['10.10.20.0/24', '10.20.20.0/24'] as $net) {
            $rule($ifn, 'pass', "$descr: DNS/RDP a servidores $net", ['protocol' => 'TCP/UDP', 'destination_net' => $net, 'destination_port' => 'PUERTOS_SEDE', 'log' => '0']);
            $rule($ifn, 'pass', "$descr: ping a servidores $net", ['protocol' => 'ICMP', 'destination_net' => $net, 'log' => '0']);
        }
        $rule($ifn, 'block', "$descr: resto bloqueado (hub-and-spoke)");
    }
}

/* IPsec + OSPF.  $side = 'a' | 'b';  $routerid = IP única por firewall;  $passive = interfaces LAN */
function wan_ab_apply($side, $routerid, $passive) {
    $psk = trim(@file_get_contents('/root/ipsec.psk'));
    @unlink('/root/ipsec.psk');
    if (strlen($psk) < 20) {
        // sin PSK nueva: conservar la existente (permite re-ejecutar el script de sitio)
        $ipsec = new \OPNsense\IPsec\IPsec();
        foreach ($ipsec->preSharedKeys->preSharedKey->iterateItems() as $k) { $psk = (string)$k->Key; break; }
        if (strlen($psk) < 20) { fwrite(STDERR, "falta /root/ipsec.psk\n"); exit(3); }
    }

    /* --- PSK y activación --- */
    $ipsec = new \OPNsense\IPsec\IPsec();
    reset_array($ipsec->preSharedKeys->preSharedKey);
    foreach (WAN_AB_TUNNELS as [$reqid, $ifn, $descr, $ao, $bo]) {
        [$me, $peer] = $side === 'a' ? [$ao, $bo] : [$bo, $ao];
        $ipsec->preSharedKeys->preSharedKey->Add()->setNodes(['ident' => $me, 'remote_ident' => $peer,
            'keyType' => 'PSK', 'Key' => $psk, 'description' => "$descr A<->B"]);
    }
    save_model($ipsec, 'ipsec-psk');
    Config::getInstance()->save();
    // general.enabled es un LegacyLinkField -> la fuente real es <ipsec><enable> (legacy)
    $cfg = Config::getInstance()->object();
    if (!isset($cfg->ipsec)) { $cfg->addChild('ipsec'); }
    $cfg->ipsec->enable = '1';
    Config::getInstance()->save();

    /* --- Tunables: con VTI se filtra en ipsecN y no en enc0 (si no, pf descarta lo descifrado) --- */
    $tun = new \OPNsense\Core\Tunables();
    foreach (['net.enc.in.ipsec_filter_mask' => '0', 'net.enc.out.ipsec_filter_mask' => '0'] as $k => $v) {
        $node = null;
        // OJO (26.7): los tunables conocidos (net.enc.*) aparecen como entradas ESTÁTICAS (clave = md5 del nombre) que
        // NUNCA se guardan en config.xml; hay que crear/usar una entrada propia (uuid) para que persista al reiniciar.
        foreach ($tun->item->iterateItems() as $key => $it) { if ((string)$it->tunable === $k && $key !== md5($k)) { $node = $it; } }
        if (!$node) { $node = $tun->item->Add(); }
        $node->setNodes(['tunable' => $k, 'value' => $v, 'descr' => 'ACC: filtrar IPsec solo en las VTI']);
        exec('/sbin/sysctl ' . escapeshellarg("$k=$v"));
    }
    save_model($tun, 'tunables');
    Config::getInstance()->save();

    /* --- PSK de las sedes --- */
    $psk_s = trim(@file_get_contents('/root/ipsec-sedes.psk')); @unlink('/root/ipsec-sedes.psk');
    $ipsec = new \OPNsense\IPsec\IPsec();
    if (strlen($psk_s) < 20) {   // conservar la existente al re-ejecutar
        foreach ($ipsec->preSharedKeys->preSharedKey->iterateItems() as $k) { if (str_contains((string)$k->remote_ident, 'kit-sede')) { $psk_s = (string)$k->Key; break; } }
    }
    if (strlen($psk_s) >= 20) {
        foreach (sede_tunnels($side) as [$reqid, $ifn, $descr, $lo, , $fq]) {
            $ipsec->preSharedKeys->preSharedKey->Add()->setNodes(['ident' => $lo, 'remote_ident' => $fq,
                'keyType' => 'PSK', 'Key' => $psk_s, 'description' => "$descr"]);
        }
        save_model($ipsec, 'ipsec-psk-sedes'); Config::getInstance()->save();
    } else { fwrite(STDERR, "aviso: sin /root/ipsec-sedes.psk, túneles de sedes sin PSK\n"); }

    /* --- swanctl: conexiones, locals, remotes, children, VTI --- */
    $sw = new \OPNsense\IPsec\Swanctl();
    foreach (['Connections' => 'Connection', 'locals' => 'local', 'remotes' => 'remote',
              'children' => 'child', 'VTIs' => 'VTI'] as $c => $i) { reset_array($sw->$c->$i); }
    foreach (WAN_AB_TUNNELS as [$reqid, $ifn, $descr, $ao, $bo, $ai, $bi]) {
        [$me, $peer, $in_me, $in_peer] = $side === 'a' ? [$ao, $bo, $ai, $bi] : [$bo, $ao, $bi, $ai];
        $conn = $sw->Connections->Connection->Add();
        $conn->setNodes(['enabled' => '1', 'proposals' => 'default', 'version' => '2', 'unique' => 'replace', 'mobike' => '0',
            'local_addrs' => $me, 'remote_addrs' => $peer, 'dpd_delay' => '5', 'dpd_timeout' => '15',
            'keyingtries' => '0', 'description' => "$descr A<->B"]);
        $cu = $conn->getAttributes()['uuid'];
        $sw->locals->local->Add()->setNodes(['enabled' => '1', 'connection' => $cu, 'round' => '0',
            'auth' => 'psk', 'id' => $me, 'description' => "$descr local"]);
        $sw->remotes->remote->Add()->setNodes(['enabled' => '1', 'connection' => $cu, 'round' => '0',
            'auth' => 'psk', 'id' => $peer, 'description' => "$descr remoto"]);
        $sw->children->child->Add()->setNodes(['enabled' => '1', 'connection' => $cu, 'reqid' => (string)$reqid,
            'esp_proposals' => 'default', 'mode' => 'tunnel', 'policies' => '0',
            'start_action' => $side === 'b' ? 'start' : 'none',
            'dpd_action' => $side === 'b' ? 'start' : 'clear', 'close_action' => 'none',
            'local_ts' => '0.0.0.0/0', 'remote_ts' => '0.0.0.0/0', 'description' => "$descr child"]);
        $sw->VTIs->VTI->Add()->setNodes(['enabled' => '1', 'reqid' => (string)$reqid, 'local' => $me,
            'remote' => $peer, 'tunnel_local' => $in_me, 'tunnel_remote' => $in_peer, 'description' => $descr]);
    }
    foreach (sede_tunnels($side) as [$reqid, $ifn, $descr, $lo, $pub, $fq, $il, $is]) {   // sedes: solo RESPONDEMOS
        $conn = $sw->Connections->Connection->Add();
        $conn->setNodes(['enabled' => '1', 'proposals' => 'default', 'version' => '2', 'unique' => 'replace', 'mobike' => '0',
            'local_addrs' => $lo, 'remote_addrs' => $pub, 'encap' => '1', 'dpd_delay' => '10', 'dpd_timeout' => '30',
            'keyingtries' => '0', 'description' => "$descr"]);
        $cu = $conn->getAttributes()['uuid'];
        $sw->locals->local->Add()->setNodes(['enabled' => '1', 'connection' => $cu, 'round' => '0', 'auth' => 'psk', 'id' => $lo, 'description' => "$descr local"]);
        $sw->remotes->remote->Add()->setNodes(['enabled' => '1', 'connection' => $cu, 'round' => '0', 'auth' => 'psk', 'id' => $fq, 'description' => "$descr sede"]);
        $sw->children->child->Add()->setNodes(['enabled' => '1', 'connection' => $cu, 'reqid' => (string)$reqid,
            'esp_proposals' => 'default', 'mode' => 'tunnel', 'policies' => '0', 'start_action' => 'none',
            'dpd_action' => 'clear', 'close_action' => 'none', 'local_ts' => '0.0.0.0/0', 'remote_ts' => '0.0.0.0/0', 'description' => "$descr child"]);
        $sw->VTIs->VTI->Add()->setNodes(['enabled' => '1', 'reqid' => (string)$reqid, 'local' => $lo, 'remote' => $pub,
            'tunnel_local' => $il, 'tunnel_remote' => $is, 'description' => $descr]);
    }
    save_model($sw, 'swanctl');
    Config::getInstance()->save();

    /* --- OSPF (FRR) --- */
    $gen = new \OPNsense\Quagga\General();
    $gen->enabled = '1';
    save_model($gen, 'frr-general');
    $ospf = new \OPNsense\Quagga\OSPF();
    $ospf->enabled = '1';
    $ospf->routerid = $routerid;
    $ospf->logadjacencychanges = '1';
    $au = null;                               // reutiliza el área 0 si ya existe (re-ejecución)
    foreach ($ospf->areas->area->iterateItems() as $uuid_a => $a) {
        if ((string)$a->id === '0.0.0.0') { $au = $uuid_a; }
    }
    if (!$au) {
        $area = $ospf->areas->area->Add();
        $area->setNodes(['enabled' => '1', 'id' => '0.0.0.0']);
        $au = $area->getAttributes()['uuid'];
    }
    save_model($ospf, 'ospf-area');           // el área debe existir en config antes de referenciarla
    Config::getInstance()->save();
    // ModelRelationField cachea el modelo relacionado dentro del proceso: las interfaces se escriben
    // directamente en config.xml (formato del modelo, con uuid); se validan al recargar el modelo.
    $x = Config::getInstance()->object()->OPNsense->quagga->ospf->interfaces;
    while (isset($x->interface[0])) { unset($x->interface[0]); }
    $uuid = function () { $h = bin2hex(random_bytes(16));
        return substr($h, 0, 8) . '-' . substr($h, 8, 4) . '-4' . substr($h, 13, 3) . '-a' . substr($h, 17, 3) . '-' . substr($h, 20, 12); };
    $addif = function (array $f) use ($x, $uuid) {
        $n = $x->addChild('interface'); $n->addAttribute('uuid', $uuid());
        foreach ($f as $k => $v) { $n->addChild($k, $v); }
    };
    foreach (WAN_AB_TUNNELS as [$reqid, $ifn, $descr, , , , , $cost]) {
        $addif(['enabled' => '1', 'interfacename' => $ifn, 'area' => $au, 'cost' => (string)$cost,
            'networktype' => 'point-to-point', 'hellointerval' => '2', 'deadinterval' => '8']);
    }
    foreach (sede_tunnels($side) as [$reqid, $ifn, , , , , , , $cost]) {
        $addif(['enabled' => '1', 'interfacename' => $ifn, 'area' => $au, 'cost' => (string)$cost,
            'networktype' => 'point-to-point', 'hellointerval' => '2', 'deadinterval' => '8']);
    }
    foreach ($passive as $ifn) {
        $addif(['enabled' => '1', 'interfacename' => $ifn, 'area' => $au, 'passive' => '1']);
    }
    Config::getInstance()->save();
    echo "ok: ospf-interfaces (" . (count(WAN_AB_TUNNELS) + count(sede_tunnels($side)) + count($passive)) . ")\n";

    if ($side === 'b') { acc_vigia_ipsec(); }
    acc_ids();
}

/*
 * Vigía de los túneles A<->B (solo en fw-b, que es quien INICIA). En un arranque en frío, si fw-b intenta antes de que
 * fw-a1 tenga IPsec cargado recibe NO_PROPOSAL_CHOSEN y strongSwan NO reintenta (error permanente): A<->B quedaba caído
 * hasta intervención manual. Cron de OPNsense cada minuto: relanza cada hijo con "dpd action start" que no tenga SA.
 */
function acc_vigia_ipsec() {
    file_put_contents('/usr/local/sbin/acc-vigia-ipsec.sh', <<<'SH'
#!/bin/sh
# ACC: relanza los túneles IPsec que este firewall inicia (dpd action start) si no tienen SA instalada.
swanctl --list-conns 2>/dev/null | awk '/^[^ ].*: IKEv/ {ike=$1; sub(/:$/, "", ike)}
  /^  [^ ]+: TUNNEL.*dpd action is start/ {c=$1; sub(/:$/, "", c); print ike, c}' |
while read ike child; do
  swanctl --list-sas --ike "$ike" 2>/dev/null | grep -q INSTALLED && continue
  logger -t acc-vigia "túnel $ike sin SA: se relanza"
  swanctl --initiate --ike "$ike" --child "$child" --timeout 10 >/dev/null 2>&1 &
done
wait
SH
    );
    chmod('/usr/local/sbin/acc-vigia-ipsec.sh', 0755);
    acc_acciones();
    $cron = new \OPNsense\Cron\Cron();
    $job = null;
    foreach ($cron->jobs->job->iterateItems() as $j) { if ((string)$j->command === 'acc vigia-ipsec') { $job = $j; } }
    if (!$job) { $job = $cron->jobs->job->Add(); }
    $job->setNodes(['enabled' => '1', 'minutes' => '*', 'hours' => '*', 'days' => '*', 'months' => '*', 'weekdays' => '*',
        'who' => 'root', 'command' => 'acc vigia-ipsec', 'parameters' => '', 'description' => 'ACC: vigía de túneles A<->B']);
    save_model($cron, 'cron-vigia-ipsec');
    Config::getInstance()->save();
    exec('/usr/local/sbin/configctl cron restart >/dev/null 2>&1');
}


/*
 * IDS/IPS (Fase 1 alcance, RQ-09): Suricata en modo IDS (pcap) en las dos WAN, reglas ET Open de escaneo, DoS, exploits y
 * respuestas de ataque. "Prevención" por respuesta activa: el vigía (cron cada minuto) lee las alertas nuevas de eve.json,
 * añade la IP de origen a la tabla ACC_IDS_BLOQUEO (bloqueada en las WAN, caduca a la hora) si no es de confianza
 * (redes del laboratorio, sedes, el otro sitio, DNS públicos) y envía a Zabbix (trapper) el n.º de alertas y la última firma.
 */
function acc_ids() {
    $ids = new \OPNsense\IDS\IDS();
    $g = $ids->general;
    $g->enabled = '1'; $g->mode = 'pcap'; $g->promisc = '0'; $g->interfaces = 'wan,opt1';
    $g->homenet = '10.0.0.0/8,172.16.0.0/12,192.168.0.0/16,100.64.0.0/10,203.0.113.0/24,198.51.100.0/24,192.0.2.0/24';
    $g->detect->Profile = 'low';   // memoria: los FW del laboratorio tienen 1–1.5 GB
    $want = ['emerging-scan.rules', 'emerging-dos.rules', 'emerging-exploit.rules', 'emerging-attack_response.rules'];
    $have = [];
    foreach ($ids->files->file->iterateItems() as $fl) { $have[(string)$fl->filename] = $fl; }
    foreach ($want as $fn) { $n = $have[$fn] ?? $ids->files->file->Add(); $n->filename = $fn; $n->enabled = '1'; }
    save_model($ids, 'ids');
    Config::getInstance()->save();

    file_put_contents('/usr/local/sbin/acc-ids-vigia.py', <<<'PYS'
#!/usr/local/bin/python3
# ACC: respuesta activa del IDS (Suricata) + aviso a Zabbix. Lo lanza el cron de OPNsense cada minuto (configd: acc ids-vigia).
import ipaddress, json, os, socket, struct, subprocess
EVE, POS, TABLA = "/var/log/suricata/eve.json", "/var/db/acc-ids.pos", "ACC_IDS_BLOQUEO"
HOST = socket.gethostname().split(".")[0]
CONFIANZA = [ipaddress.ip_network(n) for n in ("10.0.0.0/8", "172.16.0.0/12", "192.168.0.0/16", "100.64.0.0/10", "203.0.113.0/24",
             "198.51.100.0/24", "192.0.2.0/24", "1.1.1.1/32", "1.0.0.1/32", "8.8.8.8/32", "8.8.4.4/32")]
def confianza(ip):
    try: a = ipaddress.ip_address(ip)
    except ValueError: return True
    return any(a in n for n in CONFIANZA)
def zabbix(datos):
    body = json.dumps({"request": "sender data", "data": [{"host": HOST, "key": k, "value": str(v)} for k, v in datos.items()]}).encode()
    try:
        with socket.create_connection(("10.10.20.30", 10051), timeout=5) as s:
            s.sendall(b"ZBXD\x01" + struct.pack("<II", len(body), 0) + body); s.recv(1024)
    except OSError: pass
size = os.path.getsize(EVE) if os.path.exists(EVE) else 0
try: pos = int(open(POS).read())
except (OSError, ValueError): pos = size          # primera vez: solo lo nuevo
if pos > size: pos = 0                            # rotación del registro
n, ultima, bloquear = 0, "", set()
if size > pos:
    with open(EVE, "rb") as f:
        f.seek(pos)
        for linea in f:
            try: e = json.loads(linea)
            except ValueError: continue
            if e.get("event_type") != "alert": continue
            n += 1; src = e.get("src_ip", ""); sig = e.get("alert", {}).get("signature", "?")
            ultima = f"{sig} (origen {src} -> {e.get('dest_ip', '')}:{e.get('dest_port', '')})"
            if not confianza(src): bloquear.add(src)
        pos = f.tell()
open(POS, "w").write(str(pos))
for ip in sorted(bloquear):
    if subprocess.run(["/sbin/pfctl", "-t", TABLA, "-T", "add", ip], capture_output=True).returncode == 0:
        subprocess.run(["/usr/bin/logger", "-t", "acc-ids", f"IP {ip} bloqueada 1 h en las WAN (respuesta activa del IDS)"])
subprocess.run(["/sbin/pfctl", "-t", TABLA, "-T", "expire", "3600"], capture_output=True)
r = subprocess.run(["/sbin/pfctl", "-t", TABLA, "-T", "show"], capture_output=True, text=True)
datos = {"ids.alertas": n, "ids.bloqueadas": len(r.stdout.split()) if r.returncode == 0 else 0}
if ultima: datos["ids.ultima"] = ultima[:250]
zabbix(datos)
PYS
    );
    chmod('/usr/local/sbin/acc-ids-vigia.py', 0755);
    acc_acciones();
    $cron = new \OPNsense\Cron\Cron();
    $job = null;
    foreach ($cron->jobs->job->iterateItems() as $j) { if ((string)$j->command === 'acc ids-vigia') { $job = $j; } }
    if (!$job) { $job = $cron->jobs->job->Add(); }
    $job->setNodes(['enabled' => '1', 'minutes' => '*', 'hours' => '*', 'days' => '*', 'months' => '*', 'weekdays' => '*',
        'who' => 'root', 'command' => 'acc ids-vigia', 'parameters' => '', 'description' => 'ACC: vigía del IDS (respuesta activa)']);
    save_model($cron, 'cron-ids-vigia');
    Config::getInstance()->save();
    exec('/usr/local/sbin/configctl cron restart >/dev/null 2>&1');
}

/* configd tarda unos segundos en volver a cargar sus acciones: el cron solo acepta comandos que ya lista */
function acc_esperar_accion($accion) {
    for ($i = 0; $i < 30; $i++) {
        $out = []; exec('/usr/local/sbin/configctl configd actions 2>/dev/null', $out);
        foreach ($out as $l) { if (strpos($l, $accion . ' ') === 0) { return; } }
        sleep(1);
    }
    fwrite(STDERR, "aviso: configd no lista '$accion'\n");
}

/* Acciones configd del laboratorio ("acc ..."): UN archivo con todas, escrito antes de crear el modelo del cron
 * (el modelo guarda en caché la lista de comandos durante toda la ejecución de PHP). */
function acc_acciones() {
    $txt = "[vigia-ipsec]\ncommand:/usr/local/sbin/acc-vigia-ipsec.sh\nparameters:\ntype:script\n" .
           "message:ACC vigia de tuneles A-B\ndescription:ACC: relanza los tuneles IPsec A-B sin SA\n\n" .
           "[ids-vigia]\ncommand:/usr/local/sbin/acc-ids-vigia.py\nparameters:\ntype:script\n" .
           "message:ACC vigia del IDS\ndescription:ACC: respuesta activa del IDS y aviso a Zabbix\n";
    $f = '/usr/local/opnsense/service/conf/actions.d/actions_acc.conf';
    if (@file_get_contents($f) !== $txt) {
        file_put_contents($f, $txt);
        exec('/usr/sbin/service configd restart >/dev/null 2>&1');
    }
    acc_esperar_accion('acc vigia-ipsec'); acc_esperar_accion('acc ids-vigia');
}
