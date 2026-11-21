<?php
/*
 * DHCP con dnsmasq de OPNsense (RQ-13). Solo DHCP: el DNS de dnsmasq se desactiva (port=0), Unbound sigue en :53.
 * Clientes: router = VIP .1 del sitio, DNS = dc1 + dc2 (AD), dominio ad.alcaldia.lab.
 * En el Site A (CARP) cada firewall reparte un rango distinto -> sin conflictos aunque ambos respondan.
 * $nets = [ifname => [prefijo '10.10.40', inicio, fin]]
 */
use OPNsense\Core\Config;

function dhcp_apply(array $nets) {
    $d = new \OPNsense\Dnsmasq\Dnsmasq();
    reset_array($d->dhcp_ranges);
    reset_array($d->dhcp_options);
    $d->enable = '1';
    $d->port = '0';                                  // sin DNS en dnsmasq
    $d->interface = implode(',', array_keys($nets));
    foreach ($nets as $ifn => [$pfx, $ini, $fin]) {
        $d->dhcp_ranges->Add()->setNodes(['interface' => $ifn, 'start_addr' => "$pfx.$ini", 'end_addr' => "$pfx.$fin",
            'lease_time' => '3600', 'domain_type' => 'range', 'domain' => 'ad.alcaldia.lab',
            'description' => "DHCP $ifn"]);
        $d->dhcp_options->Add()->setNodes(['type' => 'set', 'option' => '3', 'interface' => $ifn,
            'value' => "$pfx.1", 'description' => 'router = VIP/gateway del sitio']);
        $d->dhcp_options->Add()->setNodes(['type' => 'set', 'option' => '6', 'interface' => $ifn,
            'value' => '10.10.20.10,10.20.20.10', 'description' => 'DNS = dc1, dc2']);
    }
    save_model($d, 'dhcp');
    Config::getInstance()->save();
}
