# Alcaldia-Digital

Simulación en GNS3 del Centro de Datos Gubernamental "Alcaldía Digital": Site A (Tier II), Site B (Tier I, sitio tibio) y 3 sedes distritales con su kit replicable.

- Plan maestro: [PLAN_DESARROLLO.md](PLAN_DESARROLLO.md)
- Estado vivo (léelo primero): [ESTADO.md](ESTADO.md)
- Reglas para agentes IA: [AGENTS.md](AGENTS.md)
- Bitácora: [docs/bitacora/](docs/bitacora/) · Pruebas y evidencias: [docs/pruebas/](docs/pruebas/)
- Direccionamiento: [inventory/ipam.md](inventory/ipam.md) · Topología: [topology/topologia.md](topology/topologia.md)

## Arranque rápido

```bash
cp .env.example .env            # rellenar
sudo bash scripts/host-prep.sh  # módulos bonding/openvswitch/8021q
bash scripts/get-opnsense.sh    # imagen QEMU de OPNsense
bash scripts/pull-images.sh     # imágenes oficiales con versión fijada
bash scripts/build-images.sh    # imágenes propias acc/*
bash scripts/gns3-templates.sh  # plantillas ACC-* en GNS3
```

## Operación diaria
Apagar y encender el laboratorio: [APAGAR-ENCENDER.md](APAGAR-ENCENDER.md)
