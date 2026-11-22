# F6 — Kits de sede ×3 (hub-and-spoke) (2026-11-21)

Kit replicable (`scripts/new-sede.sh N` + `scripts/sede-setup.sh N`) = equivalente al FortiGate 40F: Alpine + strongSwan (swanctl, interfaces **XFRM** route-based) + FRR (OSPF) + nftables + dnsmasq. Cada sede: kit, switch OVS, 2 PC (Sede 1: pc-01-b gráfico).

| Sede | ISP | WAN (CGNAT) | IP pública (pool CGNAT) | LAN |
|---|---|---|---|---|
| 1 | ISP1 | 100.64.1.2 | 203.0.113.251 | 10.100.1.0/24 |
| 2 | ISP2 | 100.64.2.2 | 198.51.100.252 | 10.100.2.0/24 |
| 3 | ISP1 | 100.64.3.2 | 203.0.113.253 | 10.100.3.0/24 |

Túneles por sede (todos **iniciados por la sede**, NAT-T, IKEv2 + PSK de sedes en `.env`, identidad FQDN `kit-sede-NN.alcaldia.lab`):
A por WAN1 (VIP 203.0.113.4, coste 10, 172.16.N.0/30) · A por WAN2 (VIP 198.51.100.4, coste 20, 172.16.N.4/30) · B (203.0.113.10, coste 100, 172.16.N.8/30).
En los sitios: VTI `ipsec1N`/`ipsec2N` (A) e `ipsec3N` (B); reglas: OSPF, DNS (53) y RDP (3389) + ping hacia 10.10.20.0/24 y 10.20.20.0/24; **todo lo demás bloqueado y registrado**.

| # | Prueba | Resultado | Requisito |
|---|---|---|---|
| 1 | Túneles a través del CGNAT | ✅ 9/9 ESTABLISHED (3 por sede) | RQ-08, Fase-1 §6.1 |
| 2 | OSPF | ✅ 3/3 Full por sede, 29 rutas | — |
| 3 | DHCP en la sede | ✅ pc-01-a 10.100.1.176, DNS dc1 | RQ-13 |
| 4 | Servicios desde la sede | ✅ DNS dc1/dc2, ping dc1, RDP a ts1, Internet local, portal público | RQ-01/02 |
| 5 | **Aislamiento** | ✅ sede1→sede2 bloqueado (registrado en fw-a1 `ipsec11`), gestión, NAS y puertos internos bloqueados | RQ-09 |
| 6 | **Caída de WAN1 del Site A** | ✅ conmuta a `vti-a2` en **≈ 7,5 s** (15/120 a 500 ms) | RQ-08 |
| 7 | **Site A inalcanzable (WAN1+WAN2)** | ✅ conmuta al Site B por `vti-b` en **≈ 7 s**; dc2 resuelve el dominio | Fase-5 P-A |
| 8 | Recuperación | ✅ al volver el Site A: 3 túneles, 3 OSPF Full, ruta por vti-a1 | — |

## Problemas resueltos
- CGNAT compartido: un mismo IP público para dos sedes impediría distinguir sus túneles por dirección → **pool CGNAT** (una IP pública por sede).
- OSPF en `ExStart`: MTU distinta (XFRM 1500 vs VTI OPNsense 1400) → MTU 1400 en el kit + `ip ospf mtu-ignore`.
- Sin túneles, el tráfico al CD salía por la ruta por defecto (Internet) → ruta *blackhole* 10.0.0.0/8 (métrica 250) en el kit.

## Puesto de funcionario unido al dominio (puesto-01, Sede 1)
Imagen `acc/puesto-linux` (Debian 13 + XFCE + winbind + LightDM sobre el display VNC de GNS3). Firewall: desde las sedes y USUARIOS solo hacia dc1/dc2 los puertos de cliente de AD (`PUERTOS_AD_CLIENTE`: 53, 88, 123, 135, 389, 445, 464, 636, 3268-3269, 49152-65535); el resto de servidores sigue cerrado.

| # | Prueba | Resultado |
|---|---|---|
| P1 | Unión al dominio a través del túnel de la sede (`net ads join`) | ✅ `Joined 'PUESTO-01' to dns domain 'ad.alcaldia.lab'` |
| P2 | Pantalla de login gráfica | ✅ img/F6-puesto-login.png |
| P3 | Login de tecnico.soporte con su cuenta del AD | ✅ escritorio XFCE, home `/home/ALCALDIA/tecnico.soporte` creado (img/F6-puesto-escritorio-dominio.png) |
| P4 | Login de ana.funcionaria fuera de horario | ✅ ventana con el motivo, registro y cierre de sesión; vuelve el login (img/F6-puesto-fuera-de-horario.png) |
| P5 | Puertos de AD solo hacia los DC | ✅ dc1/dc2 abiertos; ts1:445 bloqueado |
