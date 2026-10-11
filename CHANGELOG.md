# Changelog

## 1.0.0 — 2026-10-11

- Instalación/actualización de Go desde la API oficial de go.dev con
  verificación de SHA-256 antes de instalar.
- Idempotente: no descarga si la versión instalada es la última.
- Comando `go-update` (con copia local del instalador y fallback a la red).
- PATH configurable: `/etc/profile.d/go.sh` + `~/.bashrc`/`~/.profile`/`~/.zshrc`.
- Opciones: `--check`, `--list`, `--go-version`, `--prefix`, `--no-path`,
  `--dry-run`, `--force`, `--uninstall`, `--yes`, `--help`.
- Pruebas `tests/smoke.sh` y lint ShellCheck.