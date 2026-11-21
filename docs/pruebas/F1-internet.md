# F1 — Internet simulado (2026-11-21)

Proyecto `ACC-Lab`. Nodos: `internet-real` (NAT GNS3 → virbr0), `inet-core` (AS65000), `isp1` (AS65001), `isp2` (AS65002), `atacante-ext`.

| Prueba | Resultado | Evidencia |
|---|---|---|
| BGP inet-core ↔ isp1 / isp2 | ✅ Established | isp1 recibe `0.0.0.0/0`, `198.18.0.0/24` y `198.51.100.0/24` por BGP |
| Bloques públicos accesibles desde "Internet" | ✅ | atacante-ext → 203.0.113.254 y 198.51.100.254 (ping OK) |
| Salida real (ping 1.1.1.1) desde los 4 nodos | ✅ | RTT ≈ 35 ms |
| HTTPS real (`curl https://cloudflare.com`) | ✅ | HTTP 301 en ~0.17 s desde isp1, isp2, inet-core y atacante-ext |
| Ruta | ✅ | isp1 → 192.0.2.1 (inet-core) → 192.168.122.1 (virbr0) → 192.168.1.1 (router de casa) → 10.142.16.1 (CGNAT del proveedor real) |
| Persistencia tras reiniciar los nodos | ✅ | direcciones, FRR y nftables intactos (desplegados con `scripts/deploy-config.sh`) |

CGNAT de sedes preparado (sin probar aún, faltan las sedes): isp1 100.64.1.0/30 y 100.64.3.0/30 → SNAT 203.0.113.254; isp2 100.64.2.0/30 → SNAT 198.51.100.254.
