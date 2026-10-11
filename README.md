# go-installer

Instalación y **actualización automática** de Go (golang) en Linux Mint y Ubuntu
desde el canal oficial de `go.dev`. Un solo script, verificable con SHA-256, sin
PPA ni Snap.

```bash
curl -fsSL https://raw.githubusercontent.com/bioodev/go-installer/main/install.sh | bash
```

> **Buenas prácticas:** revisa el script antes de ejecutarlo a ciegas.
> `curl -fsSLO ... && less install.sh && bash install.sh`

## Qué hace

1. Consulta [go.dev/VERSION](https://go.dev/VERSION?m=text) para conocer la
   última versión estable y detecta la arquitectura (`uname -m`).
2. Descarga el archivo `goX.Y.Z.linux-<arch>.tar.gz` desde `go.dev/dl` y
   **verifica su SHA-256** contra el catálogo oficial (`?mode=json`) antes de
   tocar nada.
3. Reemplaza por completo `/usr/local/go` (borra la anterior y extrae de cero,
   como recomienda la [guía oficial](https://go.dev/doc/install)).
4. Añade `/usr/local/go/bin` y `$HOME/go/bin` al `PATH`
   (`/etc/profile.d/go.sh` + `~/.bashrc`, `~/.profile` y `~/.zshrc` si existen).
5. Instala el comando **`go-update`**, que vuelve a ejecutar este instalador
   cada vez que quieras actualizar (o desde un temporizador).

La ejecución es **idempotente**: si ya está la última versión, no descarga nada.

## Requisitos

- Linux Mint 20+ / Ubuntu 20.04+ (también vale cualquier Linux con glibc).
- `curl`, `tar`, `sha256sum`, `awk`, `getent` (casi siempre presentes; el script
  indica el `apt install` necesario si falta alguno).
- `sudo` para escribir en `/usr/local` (o usa `--prefix`).

## Uso

| Comando | Efecto |
| --- | --- |
| `curl -fsSL …/install.sh \| bash` | Instala la última versión estable |
| `go-update` | Actualiza a la última versión estable |
| `go-update --check` | Solo comprueba (salida 0 = al día, 10 = hay novedad) |
| `bash install.sh --go-version 1.26.3` | Instala/fija una versión concreta |
| `bash install.sh --list` | Lista las últimas versiones publicadas |
| `bash install.sh --check` | Comprueba sin instalar |
| `bash install.sh --dry-run` | Muestra el plan sin descargar ni escribir |
| `bash install.sh --prefix ~/.local` | Instala sin `sudo` (usuario) |
| `bash install.sh --no-path` | No modifica ningún perfil de shell |
| `bash install.sh --uninstall` | Desinstala y limpia todo lo añadido |

Códigos de salida: `0` = ok, `1` = error, `2` = uso incorrecto,
`10` = hay actualización disponible (modo `--check`).

## Cómo funciona

- **Fuente oficial:** la API `https://go.dev/dl/?mode=json&include=all` publica
  para cada archivo su nombre, arquitectura y `sha256`. El script extrae el
  checksum del archivo exacto que va a descargar y lo comprueba con `sha256sum`
  antes de descomprimir; si no coincide, cancela y no deja nada instalado.
- **Reemplazo limpio:** nunca extrae encima de una instalación anterior
  (rompe Go según la documentación oficial): borra primero `/usr/local/go`.
- **`go-update`:** usa una copia local del instalador guardada en
  `/usr/local/lib/go-installer/install.sh`; si no hay conexión, la utiliza. Si
  la copia local no existe, baja el instalador desde este repositorio.

## Fijar una versión y coexistir con otras instalaciones

- `--go-version` fija una versión (acepta `1.26.3` o `go1.26.3`). Sin esa
  bandera, el script rechaza **degradar** a una versión más antigua que la
  instalada (usa `--force` solo si lo necesitas).
- Si detecta otro Go en el `PATH` (p. ej. uno instalado con `apt` o en
  `~/.local/go`), avisa. Comprueba cuál se ejecuta con `which -a go` y `go
  version`. `go-update` y este instalador no tocan esas otras instalaciones.
- Para mantener varias versiones en paralelo, cada versión debe vivir en un
  directorio propio (no es el objetivo de este script).

## Desarrollo

```bash
bash -n install.sh                # sintaxis
bash tests/smoke.sh               # pruebas (requiere red; descarga ~75 MB)
bash tests/smoke.sh --skip-download
```

Las pruebas usan un prefijo temporal y un `HOME` ficticio: **no tocan el sistema
real** (más detalles en [docs/architecture.md](docs/architecture.md)).

## Licencia

MIT — ver [LICENSE](LICENSE). Repositorio: https://github.com/bioodev/go-installer