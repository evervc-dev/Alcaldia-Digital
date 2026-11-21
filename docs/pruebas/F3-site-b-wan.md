# F3 — Site B (Tier I) y WAN entre sitios (2026-11-21)

Nodos nuevos: `fw-b` (OPNsense 1 GB), `sw-b1` / `sw-b2` (OVS), `adm-pc-b` (VLAN 40 B).
Configuración: `config/opnsense/site-b.php` + `config/opnsense/wan-ab.inc.php` (incluido también por site-a.php).

## Diseño de la WAN A↔B
| Túnel | Ruta | Extremos externos | VTI | Interior | Coste OSPF |
|---|---|---|---|---|---|
| T1 | ISP1 | A 203.0.113.4 (VIP CARP) ↔ B 203.0.113.10 | ipsec1 (opt8) | 172.16.0.1 ↔ .2 | 10 |
| T2 | ISP2 | A 198.51.100.4 (VIP CARP) ↔ B 198.51.100.10 | ipsec2 (opt9) | 172.16.0.5 ↔ .6 | 20 |

IKEv2 + PSK (en `.env`, fuera de git), ESP AES-GCM. **B inicia y A solo responde.** Así el nodo BACKUP del CARP nunca abre túneles; tras un failover, B reconecta por DPD contra el nuevo MASTER. OSPF área 0 con hello 2 s / dead 8 s; las VLAN se anuncian como interfaces pasivas.

## Pruebas
| # | Prueba | Resultado |
|---|---|---|
| 1 | Túneles y adyacencias | ✅ 2 SA ESTABLISHED/INSTALLED; OSPF Full por ipsec1 e ipsec2; B aprende 10.10.{10..60}.0/24 por ipsec1 (coste 10) |
| 2 | Tráfico entre sitios | ✅ adm-pc-b (10.20.40.50) ↔ adm-pc (10.10.40.50), RTT ≈ 5 ms |
| 3 | **Caída de ISP1 (lado A) con tráfico entre sitios** | ✅ **≈ 6,4 s** de corte (32/199 a 200 ms); la ruta pasa a ipsec2 / ISP2 |
| 4 | **Caída de fw-a1 (CARP) con túneles activos** | ✅ **≈ 36 s** hasta recuperar el tráfico A↔B (DPD 5 s/15 s + IKE + OSPF con fw-a2). Al volver fw-a1, preempt y recuperación automáticas |

> Mejora posible: bajar DPD a 2 s/6 s para reducir el caso 4. El valor actual está muy por debajo del RTO más exigente (S1 = 2 h).

## Errores encontrados (resueltos)
1. `dpd_action=restart` no existe en 26.7 → opciones válidas: `clear | trap | start`.
2. OSPF "Related Area not found": ModelRelationField cachea el modelo relacionado dentro del proceso → el área se guarda primero y las interfaces se escriben en config.xml.
3. IPsec no arrancaba: `general.enabled` es un LegacyLinkField → hay que fijar `<ipsec><enable>1`.
4. IKE bloqueado en WAN: las conexiones swanctl no generan reglas automáticas → reglas explícitas UDP 500/4500 + ESP desde la IP del par.
5. Tráfico descifrado bloqueado en `enc0`, y el grupo "ipsec" no existe en las reglas MVC → tunables `net.enc.{in,out}.ipsec_filter_mask=0`: se filtra solo en las VTI.
