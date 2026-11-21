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

/* Asignación de las interfaces VTI (sin IP: la pone el VTI) */
function wan_ab_interfaces($ifs) {
    foreach (WAN_AB_TUNNELS as [$reqid, $ifn, $descr]) {
        $n = $ifs->addChild($ifn);
        $n->addChild('if', "ipsec$reqid");
        $n->addChild('descr', $descr);
        $n->addChild('enable', '1');
    }
}

/* Reglas: todo lo que entra por los túneles entre sitios está permitido (el filtrado fino es por zona) */
function wan_ab_rules($rule, $side) {
    // En 26.x las conexiones swanctl NO generan reglas automáticas en WAN: IKE/NAT-T y ESP explícitos
    $wanif = [1 => 'wan', 2 => 'opt1'];
    foreach (WAN_AB_TUNNELS as [$reqid, $ifn, $descr, $ao, $bo]) {
        $peer = $side === 'a' ? $bo : $ao;
        $rule($wanif[$reqid], 'pass', "$descr: IKE/NAT-T desde el par", ['protocol' => 'UDP',
            'source_net' => "$peer/32", 'destination_port' => 'PUERTOS_IKE', 'log' => '0']);
        $rule($wanif[$reqid], 'pass', "$descr: ESP desde el par", ['protocol' => 'ESP',
            'source_net' => "$peer/32", 'log' => '0']);
        $rule($ifn, 'pass', "$descr: tráfico entre sitios y OSPF", ['log' => '0']);
    }
    // (el filtrado en enc0 se desactiva con tunables en wan_ab_apply: se filtra solo en las VTI)
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
        foreach ($tun->item->iterateItems() as $it) { if ((string)$it->tunable === $k) { $node = $it; } }
        if (!$node) { $node = $tun->item->Add(); }
        $node->setNodes(['tunable' => $k, 'value' => $v, 'descr' => 'ACC: filtrar IPsec solo en las VTI']);
        exec('/sbin/sysctl ' . escapeshellarg("$k=$v"));
    }
    save_model($tun, 'tunables');
    Config::getInstance()->save();

    /* --- swanctl: conexiones, locals, remotes, children, VTI --- */
    $sw = new \OPNsense\IPsec\Swanctl();
    foreach (['Connections' => 'Connection', 'locals' => 'local', 'remotes' => 'remote',
              'children' => 'child', 'VTIs' => 'VTI'] as $c => $i) { reset_array($sw->$c->$i); }
    foreach (WAN_AB_TUNNELS as [$reqid, $ifn, $descr, $ao, $bo, $ai, $bi]) {
        [$me, $peer, $in_me, $in_peer] = $side === 'a' ? [$ao, $bo, $ai, $bi] : [$bo, $ao, $bi, $ai];
        $conn = $sw->Connections->Connection->Add();
        $conn->setNodes(['enabled' => '1', 'proposals' => 'default', 'version' => '2', 'unique' => 'replace',
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
    foreach ($passive as $ifn) {
        $addif(['enabled' => '1', 'interfacename' => $ifn, 'area' => $au, 'passive' => '1']);
    }
    Config::getInstance()->save();
    echo "ok: ospf-interfaces (" . (count(WAN_AB_TUNNELS) + count($passive)) . ")\n";
}
