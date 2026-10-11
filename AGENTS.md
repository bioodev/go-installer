# AGENTS.md

Proyecto: instalador Go (golang) por API oficial para Linux Mint/Ubuntu, con
comando `go-update`. Lengua de los documentos: español.

## Archivos clave

- `install.sh` — instalador único (bash). Todas las opciones en `--help`.
- `tests/smoke.sh` — pruebas con prefijo temporal y `HOME` ficticio; no toca el
  sistema real. Requiere red.
- `docs/` — contexto, arquitectura y ADR.

## Convenciones

- La URL base del instalador se puede sobreescribir con
  `GO_INSTALLER_RAW_BASE` (tests/mirrors) y el prefijo con
  `GO_INSTALL_PREFIX`.
- Códigos de salida: `0` ok, `1` error, `2` uso, `10` actualización disponible.
- El script debe pasar `shellcheck -S style` y `bash -n`.
- Los cambios de comportamiento requieren ADR y actualizar
  `docs/architecture.md`.

## Verificación

```bash
shellcheck -S style install.sh tests/smoke.sh
bash tests/smoke.sh
```

Emparejado con AGENTS.md global del usuario (root de OpenCode): los proyectos
viven en `~/Documentos/desarrollos`; forja personal Gitea, mirror público a
GitHub cuando aplica.