# 0001 — Instalador idempotente con comando `go-update`

- **Estado:** Accepted
- **Fecha:** 2026-10-11
- **Decisión tomada por:** bioodev

## Contexto

Se quiere instalar y mantener actualizado Go en Linux Mint/Ubuntu desde el
canal oficial (sin PPA ni Snap), con un one-liner `curl ... | bash` y
verificación del checksum publicado por Go. El catálogo `?mode=json` de go.dev
publica por archivo su nombre, arquitectura y SHA-256; la guía oficial
recomienda borrar por completo `/usr/local/go` antes de extraer, y añadir
`/usr/local/go/bin` y `$HOME/go/bin` al PATH.

## Decisión

Un único script bash (`install.sh`):

1. Resuelve la versión objetivo (última estable o fijada con `--go-version`)
   y la arquitectura, consultando `go.dev/VERSION?m=text` y `go.dev/dl?mode=json`.
2. Verifica el SHA-256 del archivo exacto antes de descomprimir; ante
   cualquier discrepancia aborta sin dejar cambios.
3. Reemplaza por completo el árbol anterior (`rm -rf` + extraer, nunca encima).
4. Configura el PATH (perfil de sistema y del usuario) con bloques marcados,
   eliminables con `--uninstall`.
5. Instala el comando `go-update`, que re-ejecuta el instalador y da la
   "auto-actualización" sin depender de teclado: `go-update` usa una copia local
   del script (`/usr/local/lib/go-installer/install.sh`) con fallback a la red.

La ejecución es idempotente: si la versión instalada ya es la objetivo, no
descarga nada.

## Consecuencias

- **Positivas:** sin dependencias de Python/jq (JSON procesado con awk);
  auditable (un solo archivo); checksum verificado; apt/Snap quedan fuera;
  `go-update` permite automatizar con cron/systemd; el flujo sigue al pie de la
  letra la guía oficial de Go.
- **Negativas/costes:** un solo prefijo por instalación (no multi-versión);
  `go-update` necesita red si se pierde la copia local; el instalador solo
  soporta arquitecturas con binario oficial.
- **Riesgo residual:** la "auto-actualización" es disparada por el usuario
  (`go-update`) y no en segundo plano, salvo que el usuario añada un temporizador;
  se prefirió explícitamente frente a un timer oculto (decisión del responsable).

## Alternativas descartadas

- **PPA/Snap:** no oficiales para Go, fuera de control del proyecto Go.
- **`apt install golang`:** versiones anticuadas; mezclarlo con `/usr/local/go`
  confunde el PATH (el script avisa si detecta otro Go).
- **Timer systemd automático (cron):** el usuario eligió actualización
  idempotente + comando `go-update` manual; un timer añadiría un servicio que
  ejecuta `sudo` sin intervención y cambia el sistema por debajo del usuario.
- **Múltiples versiones (gestor tipo GVM):** out of scope; cada versión debe
  instalarse en su propio directorio.