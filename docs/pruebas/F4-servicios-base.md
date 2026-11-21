# F4 — Servicios base: AD/DNS, DHCP (2026-11-21)

| Nodo | Rol | Red |
|---|---|---|
| dc1 | Samba AD DC 4.17 (`acc/samba-dc`), DNS interno con reenvío a 1.1.1.1 | 10.10.20.10, bond A/B (sw-a1/sw-a2 eth4, VLAN 20) |
| dc2 | DC adicional (réplica DRS) + DNS secundario | 10.20.20.10, sw-b1 eth4 (VLAN 20) |
| usr-pc | Cliente DHCP de prueba | VLAN 50 (sw-a1 eth5) |

Dominio `ad.alcaldia.lab` (NetBIOS `ALCALDIA`, RFC2307). Contraseña de administrator en `.env` (`SAMBA_ADMIN_PASS`, generada con `scripts/gen-secrets.sh`).
DHCP: dnsmasq de OPNsense (`config/opnsense/dhcp.inc.php`); en el Site A, fw-a1 reparte .100–.149 y fw-a2 .150–.199 (sin conflictos con CARP); en el Site B, .100–.199 en la VLAN 40.

| # | Prueba | Resultado | Requisito |
|---|---|---|---|
| 1 | DC operativo | ✅ SRV `_ldap._tcp`, A de dc1 y reenvío a Internet resuelven desde 127.0.0.1 | RQ-13 |
| 2 | dc2 unido como DC | ✅ `samba-tool drs showrepl --summary` → `[ALL GOOD]` | RQ-05 |
| 3 | **Réplica del directorio A→B** | ✅ cambio de contraseña en dc1 visible en dc2 en **2,2 s** (objetivo ≤ 15 min) | **RQ-05** |
| 4 | **DHCP** | ✅ usr-pc recibe 10.10.50.179/24, gateway 10.10.50.1 (VIP), DNS dc1+dc2, búsqueda `ad.alcaldia.lab` | **RQ-13** |
| 5 | **DNS secundario** | ✅ con dc1 suspendido, el cliente resuelve los SRV de Kerberos del dominio a través de dc2 (tras el timeout de dc1) | **RQ-13** |
| 6 | Aislamiento | ✅ USUARIOS → GESTION bloqueado; USUARIOS → Internet permitido | RQ-09 |

## Errores encontrados
- Debian 12 necesita `samba-ad-provision` y `samba-ad-dc` para provisionar ("Please install samba-ad-provision package").
- **Cambiar la imagen de un nodo Docker no basta con reiniciarlo**: GNS3 conserva el contenedor. Hay que borrar el nodo y recrearlo (o cerrar y reabrir el proyecto).
- USUARIOS/DMZ no llegaban al DNS secundario del Site B → reglas nuevas hacia 10.20.20.0/24 (DNS/web).
- Desde SERVIDORES no se puede hacer ping a la VIP del gateway (la política solo permite lo necesario); no afecta al bond, que monitorea por ARP.
