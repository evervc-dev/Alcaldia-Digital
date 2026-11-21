# Authelia (S1 identidad web): MFA TOTP sobre el AD. Plantilla: los ${...} los rellena scripts/services-setup.sh desde .env.
theme: auto
certificates_directory: '/config/certs/'   # CA del laboratorio (config/pki/ca.crt)
server:
  address: 'tcp://0.0.0.0:9091/'
  asset_path: '/config/assets/'
log:
  level: info
totp:
  issuer: 'Alcaldia Digital'
identity_validation:
  reset_password:
    jwt_secret: '${AUTHELIA_JWT_SECRET}'
authentication_backend:
  password_reset:
    disable: true
  ldap:
    implementation: activedirectory
    address: 'ldaps://10.10.20.10:636'
    tls:
      skip_verify: false
      minimum_version: 'TLS1.2'
    base_dn: 'DC=ad,DC=alcaldia,DC=lab'
    user: 'CN=svc-lectura,CN=Users,DC=ad,DC=alcaldia,DC=lab'
    password: '${SVC_LDAP_PASS}'
regulation:                 # fuerza bruta: 3 intentos en 2 min -> bloqueo 5 min (prueba T5)
  max_retries: 3
  find_time: 2m
  ban_time: 5m
access_control:
  default_policy: deny
  rules:
    - domain: 'portal.evervc.dev'
      resources: ['^/funcionarios([/?].*)?$']
      policy: two_factor
      subject: [['group:funcionarios'], ['group:acceso-24h']]
    - domain: 'portal.evervc.dev'
      policy: bypass
    - domain: 'archivo.evervc.dev'
      policy: two_factor
      subject: [['group:funcionarios'], ['group:acceso-24h']]
session:
  secret: '${AUTHELIA_SESSION_SECRET}'
  cookies:
    - domain: 'evervc.dev'
      authelia_url: 'https://auth.evervc.dev'
      default_redirection_url: 'https://portal.evervc.dev/funcionarios'
storage:
  encryption_key: '${AUTHELIA_STORAGE_KEY}'
  local:
    path: '/config/db.sqlite3'
notifier:
  smtp:
    address: 'smtp://10.10.20.32:1025'
    sender: 'Alcaldia Digital <no-reply@evervc.dev>'
    disable_require_tls: true
    disable_starttls: true
