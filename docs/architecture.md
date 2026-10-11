# Arquitectura

## Componentes

```
install.sh            Instalador único (bash 4+, set -Eeuo pipefail).
tests/smoke.sh        Pruebas sin efectos en el sistema real.
```

Dependencias en tiempo de ejecución: `curl`, `tar`, `sha256sum`, `awk`,
`getent`, `mktemp`. No necesita `python3` ni `jq`: el JSON del catálogo se
procesa con `awk`.

## Flujo de instalación

1. `parse_args` → modo, prefijo, versión fijada, etc.
2. `preflight` → arquitectura del sistema y herramientas mínimas.
3. `resolve_target` → versión objetivo (última estable vía
   `https://go.dev/VERSION?m=text`, o la fijada con `--go-version`, validada
   contra el catálogo) y nombre del archivo `goX.Y.Z.linux-<arch>.tar.gz`.
4. **Idempotencia:** si la versión instalada ya es la objetivo y no hay
   `--force`, termina sin descargar.
5. `fetch_checksum` → consulta el catálogo `?mode=json&include=all` (cacheado
   en `CATALOG`) y extrae el `sha256` del archivo exacto.
6. `download_archive` + `verify_archive` → descarga y comprueba SHA-256;
   si no coincide, borra el archivo y aborta.
7. `validate_tarball_layout` → comprueba que el árbol empiece por `go/` y que
   contenga `go/bin/go`.
8. `install_archive` → `rm -rf` del `GO_DIR` anterior y extracción en el
   prefijo (reemplazo completo, nunca encima).
9. `install_update_command` → genera `/usr/local/bin/go-update`.
10. `install_local_copy` → guarda este script en
    `/usr/local/lib/go-installer/install.sh` (si no hay fuente local, lo baja
    del repositorio; si falla, `go-update` seguirá funcionando por red).
11. `setup_path` → `/etc/profile.d/go.sh` (solo prefijo `/usr/local`) y bloque con
    marcadores en `~/.bashrc`, `~/.profile`, `~/.zshrc`. Cada bloque lleva una
    guarda `case ":$PATH:" in` para no duplicar rutas cuando varios perfiles se
    cargan en el mismo shell (p. ej. `/etc/profile` + `~/.profile` en un login).

`--dry-run` realiza pasos de lectura (1–5) y muestra el plan; nunca descarga ni
escribe. `--uninstall` revierte 6–11 (quita el árbol, binarios, perfiles y los
bloques con marcadores ⸺ rmdir solo borra directorios vacíos, por lo que
`/usr/local/bin` nunca se ve afectado).

## Privilegios

- `setup_sudo` decide de forma automática: usa `sudo` solo si el prefijo (o su
  padre) no es escribible. Permite `--prefix ~/.local` sin sudo.
- Al ejecutarse bajo `sudo`, los perfiles se escriben en el HOME del usuario
  original (`SUDO_USER`).

## Variables de entorno

| Variable | Efecto |
| --- | --- |
| `GO_INSTALL_PREFIX` | Prefijo de instalación (igual que `--prefix`). |
| `GO_INSTALLER_RAW_BASE` | Base alternativa para descargar este script (tests/mirrors). |
| `GO_INSTALLER_TARGET_HOME` | HOME de destino para los perfiles (solo pruebas). |
| `TMPDIR` | Directorio temporal de descarga. |

## Códigos de salida

| Código | Significado |
| --- | --- |
| 0 | Ok (instalado, al día, o `--help`/`--list`) |
| 1 | Error (red, checksum, versión no publicada, privilegios…) |
| 2 | Uso incorrecto (opción o argumento desconocido) |
| 10 | Actualización disponible (solo modo `--check`; útil para automatizar) |

## Pruebas

`tests/smoke.sh` aísla por completo: prefijo en `mktemp -d`, `HOME` ficticio
(`GO_INSTALLER_TARGET_HOME`), descarta la instalación con `--skip-download` y
valida `go-update` con `file://` (sin necesitar la publicación del repositorio).
Cubre: ayuda, listado, `--check` (0/10), rechazo de versiones inexistentes,
`--dry-run`, instalación completa, idempotencia, fijado de versión, restauración
a la última y desinstalación.