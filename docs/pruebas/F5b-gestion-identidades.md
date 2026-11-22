# F5b — Gestión de identidades por web y acceso remoto por WARP (2026-11-21)

Diseño: PLAN_DESARROLLO.md §12. Componentes: WARP Zero Trust (team `alcaldia-digital`, 4 correos autorizados en `.env`), Gateway (DNS interno de lam.evervc.dev + permiso solo a LAM:443 y ts1:3389 + bloqueo del resto de 10.10/16 y 10.20/16), Authelia (MFA, grupo `gestores-identidad`/`Domain Admins`), LAM 9.6 (10.10.20.50) con login de la cuenta AD del técnico, delegación en el AD sobre `OU=Funcionarios`.

| # | Prueba | Resultado | Quién |
|---|---|---|---|
| 1 | Gestor crea usuario en OU=Sede-02 (samba-tool como tecnico.soporte) | ✅ permitido | agente |
| 2 | Gestor crea usuario en CN=Users | ✅ denegado (`LDAP_INSUFFICIENT_ACCESS_RIGHTS`) | agente |
| 3 | Gestor añade a `acceso-24h` | ✅ denegado | agente |
| 4 | Gestor resetea la contraseña de `admin.dc` | ✅ denegado | agente |
| 5 | Gestor añade a `funcionarios`, resetea, deshabilita y borra un funcionario de su OU | ✅ permitido | agente |
| 6 | `lam.evervc.dev` vía WARP → TLS válido (Let's Encrypt) → 302 a Authelia | ✅ | agente |
| 7 | `lam.evervc.dev` sin WARP | ✅ no resuelve / no accesible | agente y usuario |
| 8 | Login completo en LAM desde un PC Windows real con WARP (MFA + cuenta AD) | ✅ | **usuario** |
| 9 | Alta de un usuario en Sede-02 desde LAM | ✅ | **usuario** |
| 10 | Modificar `admin.dc` o asignar `acceso-24h` desde LAM | ✅ denegado por el AD | **usuario** |
| 11 | Escritorio remoto (RDP) a ts1 desde un PC real vía WARP con `tecnico.soporte` | ✅ sesión XFCE operativa | **usuario** |
| 12 | MFA TOTP completo en el navegador (registro con código por mailpit) | ✅ | **usuario** |
