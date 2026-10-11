#!/usr/bin/env bash
#
#  go-installer
#  Instala y mantiene actualizado Go (golang) desde el canal oficial de go.dev.
#  Pensado para Linux Mint y Ubuntu (amd64, arm64, armv6l, 386, ppc64le, s390x, riscv64, loong64).
#
#  Instalación rápida:
#      curl -fsSL https://raw.githubusercontent.com/bioodev/go-installer/main/install.sh | bash
#
#  Auditoría antes de ejecutar (recomendado):
#      curl -fsSLO https://raw.githubusercontent.com/bioodev/go-installer/main/install.sh
#      less install.sh && bash install.sh
#
#  Licencia MIT. Repositorio: https://github.com/bioodev/go-installer
#
set -Eeuo pipefail

readonly SCRIPT_VERSION="1.0.0"
readonly REPO_OWNER="bioodev"
readonly REPO_NAME="go-installer"
readonly REPO_BRANCH="main"
readonly GO_DL_URL="https://go.dev/dl/"
readonly GO_VERSION_URL="https://go.dev/VERSION?m=text"
readonly MARK_BEGIN="# >>> go-installer (PATH de Go) >>>"
readonly MARK_END="# <<< go-installer <<<"

# Base para descargar el propio instalador (go-update y la copia local).
readonly RAW_BASE="${GO_INSTALLER_RAW_BASE:-https://raw.githubusercontent.com/${REPO_OWNER}/${REPO_NAME}/${REPO_BRANCH}}"

# Códigos de salida
readonly EX_OK=0
readonly EX_ERROR=1
readonly EX_USAGE=2
readonly EX_UPDATE_AVAILABLE=10

# ---------------------------------------------------------------------------
# Estado (sobreescribible por banderas o variables de entorno)
# ---------------------------------------------------------------------------
PREFIX="${GO_INSTALL_PREFIX:-/usr/local}"
MODE="install"
ASSUME_YES=0
FORCE=0
DRY_RUN=0
SETUP_PATH=1
PINNED_VERSION=""
SUDO=""
TMP_ROOT=""
CATALOG=""

# Derivados
GO_DIR=""
GO_BIN=""
BIN_DIR=""
LIB_DIR=""
ARCH=""
TARGET_VERSION=""
FILE=""
EXPECTED_SHA256=""
TARGET_USER=""
TARGET_HOME=""

# ---------------------------------------------------------------------------
# Salida
# ---------------------------------------------------------------------------
if [ -t 1 ]; then
  C_RESET=$'\033[0m'; C_BOLD=$'\033[1m'; C_DIM=$'\033[2m'
  C_RED=$'\033[31m'; C_GREEN=$'\033[32m'; C_YELLOW=$'\033[33m'; C_BLUE=$'\033[34m'
else
  C_RESET=""; C_BOLD=""; C_DIM=""; C_RED=""; C_GREEN=""; C_YELLOW=""; C_BLUE=""
fi

info() { printf '%s==>%s %s\n' "$C_BLUE" "$C_RESET" "$*"; }
ok()   { printf '%s  ok%s %s\n' "$C_GREEN" "$C_RESET" "$*"; }
skip() { printf '%s  --%s %s\n' "$C_DIM" "$C_RESET" "$*"; }
warn() { printf '%s aviso:%s %s\n' "$C_YELLOW" "$C_RESET" "$*" >&2; }
die()  { printf '%s error:%s %b\n' "$C_RED" "$C_RESET" "$*" >&2; exit "$EX_ERROR"; }

usage() {
  cat <<EOF
${C_BOLD}${REPO_NAME} ${SCRIPT_VERSION}${C_RESET} — instala y actualiza Go desde el canal oficial.

${C_BOLD}Uso${C_RESET}
  ./install.sh [opciones]
  curl -fsSL ${RAW_BASE}/install.sh | bash

${C_BOLD}Opciones${C_RESET}
  -c, --check            Solo comprueba; no descarga ni instala.
                         Sale 0 si está al día y 10 si hay versión nueva.
  -u, --update           Fuerza el modo actualización (por defecto).
  -f, --force            Reinstala aunque la versión ya sea la última.
      --go-version X.Y   Instala una versión concreta (p. ej. 1.26.3 o go1.26.3).
      --prefix DIR       Directorio destino; 'go' queda en DIR/go (def: /usr/local).
      --no-path          No modifica PATH ni escribe perfiles de shell.
      --dry-run          Muestra lo que haría sin descargar ni escribir nada.
  -l, --list             Lista las últimas versiones publicadas por Go.
      --uninstall        Desinstala Go y todo lo añadido por este instalador.
  -y, --yes              No pedir confirmación (para --uninstall).
  -h, --help             Muestra esta ayuda.
      --version          Muestra la versión de este script.

${C_BOLD}Variables de entorno${C_RESET}
  GO_INSTALL_PREFIX        Igual que --prefix.
  GO_INSTALLER_RAW_BASE   Base alternativa para descargar este script (tests/mirrors).
  GO_INSTALLER_TARGET_HOME  HOME de destino para los perfiles de shell (solo tests).
  TMPDIR                   Directorio temporal usado para la descarga.

${C_BOLD}Qué hace${C_RESET}
  1. Consulta ${GO_VERSION_URL} para conocer la última versión estable.
  2. Descarga el archivo linux-\$ARCH desde go.dev y verifica su SHA-256 oficial.
  3. Reemplaza por completo el directorio \$PREFIX/go (no extrae encima).
  4. Añade \$PREFIX/go/bin y \$HOME/go/bin al PATH (perfil de sistema y del usuario).
  5. Instala el comando ${C_BOLD}go-update${C_RESET}, que vuelve a ejecutar este instalador.
EOF
}

# ---------------------------------------------------------------------------
# Utilidades
# ---------------------------------------------------------------------------
need_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    die "Falta el programa '$1'. Instálalo con: ${2:-sudo apt install $1}"
  fi
}

cleanup() {
  if [ -n "$TMP_ROOT" ] && [ -d "$TMP_ROOT" ]; then
    rm -rf -- "$TMP_ROOT"
  fi
}

init_tmp() {
  TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/${REPO_NAME}.XXXXXX")" \
    || die "No se pudo crear un directorio temporal en ${TMPDIR:-/tmp}."
  trap cleanup EXIT
}

confirm() {
  if [ "$ASSUME_YES" -eq 1 ]; then
    return 0
  fi
  if [ ! -r /dev/tty ]; then
    return 1
  fi
  local reply=""
  printf '%s [s/N] ' "$1" > /dev/tty 2>/dev/null || true
  if read -r reply < /dev/tty 2>/dev/null; then
    case "$reply" in
      s|S|si|Si|sí|Sí|si.|y|Y|yes|YES) return 0 ;;
    esac
  fi
  return 1
}

parse_args() {
  while [ $# -gt 0 ]; do
    case "$1" in
      -h|--help)        usage; exit "$EX_OK" ;;
      --version)        printf '%s %s\n' "$REPO_NAME" "$SCRIPT_VERSION"; exit "$EX_OK" ;;
      -c|--check)       MODE="check" ;;
      -u|--update)      MODE="install" ;;
      -l|--list)        MODE="list" ;;
      --uninstall)      MODE="uninstall" ;;
      -f|--force)       FORCE=1 ;;
      --dry-run)        DRY_RUN=1 ;;
      --no-path)        SETUP_PATH=0 ;;
      -y|--yes)         ASSUME_YES=1 ;;
      --go-version)     shift; [ $# -gt 0 ] || die "--go-version requiere un valor."; PINNED_VERSION="$1" ;;
      --go-version=*)   PINNED_VERSION="${1#*=}" ;;
      -V)               shift; [ $# -gt 0 ] || die "-V requiere un valor."; PINNED_VERSION="$1" ;;
      --prefix)         shift; [ $# -gt 0 ] || die "--prefix requiere un directorio."; PREFIX="$1" ;;
      --prefix=*)       PREFIX="${1#*=}" ;;
      --)               shift; break ;;
      -*)               printf 'Opción desconocida: %s\n\n' "$1" >&2; usage >&2; exit "$EX_USAGE" ;;
      *)                printf 'Argumento inesperado: %s\n\n' "$1" >&2; usage >&2; exit "$EX_USAGE" ;;
    esac
    shift
  done

  # Normaliza el prefijo
  # shellcheck disable=SC2088  # '~' llega literal solo si el usuario lo entrecomilla
  case "$PREFIX" in
    '~')   PREFIX="$HOME" ;;
    '~/'*) PREFIX="$HOME/${PREFIX#\~/}" ;;
  esac
  PREFIX="${PREFIX%/}"
  if [ -z "$PREFIX" ]; then
    PREFIX="/"
  fi
}

derive_paths() {
  GO_DIR="$PREFIX/go"
  GO_BIN="$GO_DIR/bin/go"
  BIN_DIR="$PREFIX/bin"
  LIB_DIR="$PREFIX/lib/${REPO_NAME}"
}

assert_safe_paths() {
  [ -n "$PREFIX" ] || die "El prefijo está vacío."
  [ "$PREFIX" != "/" ] || die "El prefijo no puede ser /."
  case "$PREFIX" in
    *..*) die "El prefijo no puede contener '..': $PREFIX" ;;
  esac
  [ "$GO_DIR" = "$PREFIX/go" ] || die "Rutas internas inconsistentes (GO_DIR=$GO_DIR)."
}

set_target_user() {
  TARGET_USER="${SUDO_USER:-$(id -un)}"
  if [ -n "${GO_INSTALLER_TARGET_HOME:-}" ]; then
    # Solo para pruebas: dirigir los perfiles de shell a un HOME ficticio.
    TARGET_HOME="$GO_INSTALLER_TARGET_HOME"
  else
    TARGET_HOME="$(getent passwd "$TARGET_USER" | awk -F: '{print $6}')"
    if [ -z "$TARGET_HOME" ]; then
      TARGET_HOME="${HOME:-/root}"
    fi
  fi
}

preflight() {
  if [ "$(uname -s)" != "Linux" ]; then
    die "Este instalador solo soporta Linux (detectado: $(uname -s))."
  fi
  need_cmd curl     "sudo apt install curl"
  need_cmd tar      "sudo apt install tar"
  need_cmd sha256sum "sudo apt install coreutils"
  need_cmd awk      "sudo apt install gawk"
  need_cmd getent   "sudo apt install libc-bin"
  need_cmd mktemp   "sudo apt install coreutils"

  if [ -r /etc/os-release ]; then
    # shellcheck disable=SC1091
    . /etc/os-release
    case "${ID:-} ${ID_LIKE:-}" in
      *mint*|*ubuntu*|*debian*) skip "Distribución detectada: ${PRETTY_NAME:-${ID:-desconocida}}" ;;
      *) warn "Distribución no verificada (${PRETTY_NAME:-${ID:-?}}). Se asume Linux compatible con glibc." ;;
    esac
  fi

  set_target_user
}

setup_sudo() {
  SUDO=""
  if [ "$(id -u)" -eq 0 ]; then
    return 0
  fi
  if [ -d "$PREFIX" ] && [ -w "$PREFIX" ]; then
    return 0
  fi
  if [ ! -e "$PREFIX" ]; then
    local parent
    parent="$(dirname "$PREFIX")"
    if [ -d "$parent" ] && [ -w "$parent" ]; then
      return 0
    fi
  fi
  if ! command -v sudo >/dev/null 2>&1; then
    die "Se necesitan privilegios para escribir en $PREFIX y sudo no está instalado.
       Alternativa sin sudo: ./install.sh --prefix \$HOME/.local"
  fi
  info "Se necesitan privilegios para escribir en $PREFIX."
  if ! sudo -v; then
    die "No se pudo obtener sudo.
       Alternativa sin sudo: ./install.sh --prefix \$HOME/.local"
  fi
  SUDO="sudo"
}

# Ejecuta un comando con los privilegios necesarios.
as_root() {
  if [ -n "$SUDO" ]; then
    "$SUDO" "$@"
  else
    "$@"
  fi
}

# ---------------------------------------------------------------------------
# Detección de arquitectura y versiones
# ---------------------------------------------------------------------------
detect_arch() {
  case "$(uname -m)" in
    x86_64|amd64)     printf 'amd64' ;;
    aarch64|arm64)    printf 'arm64' ;;
    armv6l|armv7l|arm) printf 'armv6l' ;;
    i386|i686)        printf '386' ;;
    ppc64le)          printf 'ppc64le' ;;
    s390x)            printf 's390x' ;;
    riscv64)          printf 'riscv64' ;;
    loongarch64)      printf 'loong64' ;;
    *) return 1 ;;
  esac
}

normalize_version() {
  local v="$1"
  v="${v#"${v%%[![:space:]]*}"}"   # sin espacios a la izquierda
  v="${v#go}"
  printf 'go%s' "$v"
}

fetch_latest_version() {
  local raw line
  raw="$(curl -fsSL --retry 3 --retry-delay 2 --connect-timeout 15 "$GO_VERSION_URL")" \
    || die "No se pudo consultar $GO_VERSION_URL (¿hay conexión a internet?)."
  line="${raw%%$'\n'*}"
  line="${line%%[[:space:]]*}"
  case "$line" in
    go[0-9]*) printf '%s' "$line" ;;
    *) die "Respuesta inesperada del servidor de Go: '$line'" ;;
  esac
}

fetch_catalog() {
  local query="?mode=json"
  if [ "$1" = "all" ]; then
    query="?mode=json&include=all"
  fi
  curl -fsSL --retry 3 --retry-delay 2 --connect-timeout 15 "${GO_DL_URL}${query}" \
    || die "No se pudo consultar ${GO_DL_URL}${query}"
}

# Catálogo completo (todas las versiones publicadas), cacheado durante la ejecución.
get_catalog() {
  if [ -z "$CATALOG" ]; then
    CATALOG="$(fetch_catalog all)"
  fi
  printf '%s' "$CATALOG"
}

# Lee el catálogo JSON de go.dev y devuelve el sha256 del archivo pedido.
sha_from_catalog() {
  local json="$1" wanted="$2"
  awk -v want="$wanted" '
    /"filename"[[:space:]]*:/ {
      line = $0
      sub(/.*"filename"[[:space:]]*:[[:space:]]*"/, "", line)
      sub(/".*/, "", line)
      current = line
      next
    }
    /"sha256"[[:space:]]*:/ && current == want && !found {
      value = $0
      sub(/.*"sha256"[[:space:]]*:[[:space:]]*"/, "", value)
      sub(/".*/, "", value)
      print value
      found = 1
    }
  ' <<< "$json"
}

installed_version() {
  if [ ! -x "$GO_BIN" ]; then
    return 1
  fi
  local out
  out="$("$GO_BIN" version 2>/dev/null)" || return 1
  local _ _ ver _
  read -r _ _ ver _ <<< "$out"
  case "${ver:-}" in
    go[0-9]*) printf '%s' "$ver"; return 0 ;;
  esac
  return 1
}

# ¿$1 es una versión más nueva que $2?
is_newer() {
  local a="${1#go}" b="${2#go}"
  if [ "$a" = "$b" ]; then
    return 1
  fi
  local top
  top="$(printf '%s\n%s\n' "$a" "$b" | LC_ALL=C sort -V | awk 'END {print}')"
  [ "$top" = "$a" ]
}

resolve_target() {
  ARCH="$(detect_arch)" || die "Arquitectura no soportada: $(uname -m).
       Compila Go desde el código fuente o abre un issue con 'uname -m'."

  if [ -n "$PINNED_VERSION" ]; then
    TARGET_VERSION="$(normalize_version "$PINNED_VERSION")"
    if ! [[ "$TARGET_VERSION" =~ ^go[0-9]+\.[0-9]+(\.[0-9]+)?([a-z]+[0-9]+)?$ ]]; then
      die "Versión no válida: '$PINNED_VERSION' (usa, por ejemplo, --go-version 1.26.3)."
    fi
    FILE="${TARGET_VERSION}.linux-${ARCH}.tar.gz"
    EXPECTED_SHA256="$(sha_from_catalog "$(get_catalog)" "$FILE")"
    if [ -z "$EXPECTED_SHA256" ]; then
      die "La versión $TARGET_VERSION no está publicada para linux-${ARCH}.
       Consulta las disponibles con: $REPO_NAME --list"
    fi
  else
    TARGET_VERSION="$(fetch_latest_version)"
    FILE="${TARGET_VERSION}.linux-${ARCH}.tar.gz"
  fi
}

fetch_checksum() {
  if [ -n "$EXPECTED_SHA256" ]; then
    return 0
  fi
  EXPECTED_SHA256="$(sha_from_catalog "$(get_catalog)" "$FILE")"
  if [ -z "$EXPECTED_SHA256" ]; then
    die "No se encontró el archivo $FILE en el catálogo oficial de Go.
       Comprueba la versión con --list o usa --go-version con una versión publicada."
  fi
}

list_versions() {
  local catalog
  catalog="$(get_catalog)"
  printf '%s%-14s %s%s\n' "$C_BOLD" "VERSIÓN" "CANAL" "$C_RESET"
  awk '
    /^  "version"/ {
      v = $0; sub(/.*:[[:space:]]*"/, "", v); sub(/".*/, "", v); version = v
    }
    /^  "stable"/ {
      s = $0; sub(/.*:[[:space:]]*/, "", s); sub(/,.*/, "", s)
      if (n < 15) {
        printf "%-14s %s\n", version, (s == "true" ? "estable" : "previa")
        n++
      }
    }
  ' <<< "$catalog"
}

warn_other_installs() {
  local p
  while IFS= read -r p; do
    [ -n "$p" ] || continue
    [ "$p" = "$GO_BIN" ] && continue
    case "$p" in "$PREFIX"/*) continue ;; esac
    warn "Se detectó otra instalación de Go en $p."
    warn "Tras instalar, revisa el orden del PATH con: which -a go"
  done < <(which -a go 2>/dev/null || true)
}

# ---------------------------------------------------------------------------
# Descarga, verificación e instalación
# ---------------------------------------------------------------------------
download_archive() {
  local dest="$1"
  local quiet=(-sS)
  if [ -t 2 ]; then
    quiet=(--progress-bar)
  fi
  info "Descargando ${FILE} ..."
  if ! curl -fL --retry 3 --retry-delay 2 --connect-timeout 15 "${quiet[@]}" \
      "${GO_DL_URL}${FILE}" -o "$dest/$FILE"; then
    die "Falló la descarga de ${GO_DL_URL}${FILE}"
  fi
  ok "Descargado ($(du -h "$dest/$FILE" | cut -f1))."
}

verify_archive() {
  local file="$1" actual
  info "Verificando SHA-256 ..."
  actual="$(sha256sum "$file" | awk '{print $1}')"
  if [ "$actual" != "$EXPECTED_SHA256" ]; then
    rm -f -- "$file"
    die "El SHA-256 no coincide; se cancela la instalación.
       esperado: $EXPECTED_SHA256
       obtenido: $actual"
  fi
  ok "Checksum verificado."
}

validate_tarball_layout() {
  local file="$1" listing top
  listing="$(tar -tzf "$file")" || die "El archivo descargado no es un tar.gz válido."
  top="${listing%%$'\n'*}"
  case "$top" in
    go/*) : ;;
    *) die "El archivo no contiene un árbol 'go/' (primer entrada: '$top')." ;;
  esac
  case "$listing" in
    *$'\n'go/bin/go$'\n'*) : ;;
    *) die "El archivo no contiene la entrada 'go/bin/go'." ;;
  esac
}

install_archive() {
  local file="$1"
  if [ "$DRY_RUN" -eq 1 ]; then
    skip "[dry-run] se extraería $file en $PREFIX"
    return 0
  fi
  as_root mkdir -p "$PREFIX"
  if [ -e "$GO_DIR" ]; then
    info "Eliminando la instalación anterior en $GO_DIR."
    as_root rm -rf -- "$GO_DIR"
  fi
  info "Extrayendo en $PREFIX ..."
  as_root tar -C "$PREFIX" -xzf "$file" \
    || die "Falló la extracción del archivo."
  if [ ! -x "$GO_BIN" ]; then
    die "La extracción terminó pero no se encontró $GO_BIN."
  fi
  ok "Go instalado en $GO_DIR"
}

# ---------------------------------------------------------------------------
# PATH y comando go-update
# ---------------------------------------------------------------------------
write_system_profile() {
  local profile="/etc/profile.d/go.sh" tmp
  tmp="$TMP_ROOT/go.profile"
  cat > "$tmp" <<EOF
# Generado por ${REPO_NAME} ${SCRIPT_VERSION}. Elimina este archivo para deshacer.
if [ -d "${GO_DIR}/bin" ]; then
  case ":\${PATH}:" in
    *":${GO_DIR}/bin:"*) ;;
    *) PATH="${GO_DIR}/bin:\${PATH}" ;;
  esac
fi
export PATH
EOF
  as_root install -Dm644 "$tmp" "$profile"
  ok "Perfil de sistema actualizado: $profile"
}

add_user_path_block() {
  local rc="$1"
  if [ ! -f "$rc" ]; then
    return 0
  fi
  if grep -qF "$MARK_BEGIN" "$rc" 2>/dev/null; then
    skip "PATH ya configurado en $rc"
    return 0
  fi
  if grep -qF "${GO_DIR}/bin" "$rc" 2>/dev/null; then
    skip "PATH ya contiene ${GO_DIR}/bin en $rc"
    return 0
  fi
  # shellcheck disable=SC2016  # $HOME/$PATH deben expandirse al cargar el perfil
  printf '\n%s\nexport PATH="%s/bin:$HOME/go/bin:$PATH"\n%s\n' \
    "$MARK_BEGIN" "$GO_DIR" "$MARK_END" >> "$rc"
  ok "PATH añadido en $rc"
}

setup_path() {
  if [ "$SETUP_PATH" -eq 0 ]; then
    skip "PATH sin cambios (--no-path)."
    return 0
  fi
  if [ "$DRY_RUN" -eq 1 ]; then
    skip "[dry-run] se configuraría el PATH para ${GO_DIR}/bin"
    return 0
  fi
  if [ "$PREFIX" = "/usr/local" ]; then
    write_system_profile
  fi
  local rc
  for rc in "$TARGET_HOME/.bashrc" "$TARGET_HOME/.profile" "$TARGET_HOME/.zshrc"; do
    add_user_path_block "$rc"
  done
}

install_update_command() {
  if [ "$DRY_RUN" -eq 1 ]; then
    skip "[dry-run] se instalaría $BIN_DIR/go-update"
    return 0
  fi
  local tmp
  tmp="$TMP_ROOT/go-update"
  cat > "$tmp" <<EOF
#!/usr/bin/env bash
# go-update — generado por ${REPO_NAME} ${SCRIPT_VERSION}
# Ejecuta el instalador para dejar Go en la última versión estable.
set -Eeuo pipefail

RAW_BASE="\${GO_INSTALLER_RAW_BASE:-${RAW_BASE}}"
LOCAL_INSTALLER="${LIB_DIR}/install.sh"

tmp="\$(mktemp)"
trap 'rm -f "\$tmp"' EXIT

if curl -fsSL --retry 2 --retry-delay 2 --connect-timeout 15 "\$RAW_BASE/install.sh" -o "\$tmp"; then
  :
elif [ -r "\$LOCAL_INSTALLER" ]; then
  printf 'go-update: sin conexión, uso la copia local %s\n' "\$LOCAL_INSTALLER" >&2
  cp "\$LOCAL_INSTALLER" "\$tmp"
else
  printf 'go-update: no se pudo obtener el instalador desde %s\n' "\$RAW_BASE/install.sh" >&2
  exit 1
fi

exec bash "\$tmp" "\$@"
EOF
  if [ "$DRY_RUN" -eq 1 ]; then
    skip "[dry-run] se instalaría $BIN_DIR/go-update"
    return 0
  fi
  as_root install -Dm755 "$tmp" "$BIN_DIR/go-update"
  ok "Comando instalado: $BIN_DIR/go-update"
}

install_local_copy() {
  if [ "$DRY_RUN" -eq 1 ]; then
    skip "[dry-run] se guardaría una copia del instalador en $LIB_DIR/install.sh"
    return 0
  fi
  local src="${BASH_SOURCE[0]:-}" tmp
  tmp="$TMP_ROOT/install.sh"
  rm -f -- "$tmp"
  if [ -n "$src" ] && [ -f "$src" ] && [ -r "$src" ]; then
    cp "$src" "$tmp"
  elif ! curl -fsSL --retry 2 --connect-timeout 15 "$RAW_BASE/install.sh" -o "$tmp"; then
    skip "No se pudo guardar la copia local del instalador (go-update usará la red)."
    return 0
  fi
  as_root install -Dm755 "$tmp" "$LIB_DIR/install.sh"
  ok "Copia local del instalador: $LIB_DIR/install.sh"
}

remove_rc_block() {
  local rc="$1"
  if [ ! -f "$rc" ]; then
    return 0
  fi
  if ! grep -qF "$MARK_BEGIN" "$rc" 2>/dev/null; then
    return 0
  fi
  local tmp
  tmp="$TMP_ROOT/$(basename "$rc").clean"
  awk -v begin="$MARK_BEGIN" -v end="$MARK_END" '
    $0 == begin { skip = 1; next }
    skip && $0 == end { skip = 0; next }
    skip { next }
    { print }
  ' "$rc" > "$tmp"
  cat "$tmp" > "$rc"
  ok "Bloque de PATH eliminado de $rc"
}

# ---------------------------------------------------------------------------
# Modos
# ---------------------------------------------------------------------------
do_check() {
  local current
  current="$(installed_version || true)"
  info "Arquitectura: linux-${ARCH} | Prefijo: $PREFIX"
  if [ -n "$current" ]; then
    info "Instalada: $current"
  else
    info "Instalada: ninguna en $GO_DIR"
  fi
  info "Última estable en go.dev: $TARGET_VERSION"

  if [ -n "$PINNED_VERSION" ]; then
    if [ "$current" = "$TARGET_VERSION" ]; then
      ok "La versión solicitada ya está instalada."
      return "$EX_OK"
    fi
    info "Se instalaría $TARGET_VERSION (--go-version)."
    return "$EX_UPDATE_AVAILABLE"
  fi

  if [ -n "$current" ] && [ "$current" = "$TARGET_VERSION" ]; then
    ok "Go está al día."
    return "$EX_OK"
  fi
  if [ -n "$current" ] && is_newer "$current" "$TARGET_VERSION"; then
    ok "La versión instalada ($current) es más reciente que la estable publicada."
    return "$EX_OK"
  fi
  if [ -z "$current" ]; then
    info "Go no está instalado en este prefijo."
  else
    info "Actualización disponible: $current -> $TARGET_VERSION"
  fi
  return "$EX_UPDATE_AVAILABLE"
}

do_install() {
  local current
  current="$(installed_version || true)"

  if [ -n "$current" ] && [ "$current" = "$TARGET_VERSION" ] && [ "$FORCE" -eq 0 ]; then
    ok "Go ya está en la última versión ($current). Nada que instalar."
    setup_sudo
    install_update_command
    install_local_copy
    setup_path
    return "$EX_OK"
  fi

  if [ -n "$current" ] && [ -z "$PINNED_VERSION" ] && is_newer "$current" "$TARGET_VERSION" && [ "$FORCE" -eq 0 ]; then
    warn "La versión instalada ($current) es más nueva que la estable publicada ($TARGET_VERSION)."
    warn "No se degrada. Usa --force si de verdad quieres volver a $TARGET_VERSION."
    return "$EX_OK"
  fi

  warn_other_installs

  if [ -z "$current" ]; then
    info "Instalando Go $TARGET_VERSION (linux-${ARCH}) en $PREFIX"
  else
    info "Actualizando Go: $current -> $TARGET_VERSION"
  fi

  # Consulta el catálogo (solo lectura) para conocer el checksum oficial.
  fetch_checksum

  if [ "$DRY_RUN" -eq 1 ]; then
    skip "[dry-run] descargaría ${GO_DL_URL}${FILE}"
    skip "[dry-run] comprobaría sha256: ${EXPECTED_SHA256:0:16}…"
    skip "[dry-run] borraría $GO_DIR y extraería el archivo en $PREFIX"
    skip "[dry-run] instalaría $BIN_DIR/go-update"
    skip "[dry-run] guardaría la copia del instalador en $LIB_DIR/install.sh"
    if [ "$SETUP_PATH" -eq 1 ]; then
      skip "[dry-run] añadiría ${GO_DIR}/bin al PATH"
    fi
    return "$EX_OK"
  fi

  setup_sudo
  download_archive "$TMP_ROOT"
  verify_archive "$TMP_ROOT/$FILE"
  validate_tarball_layout "$TMP_ROOT/$FILE"
  install_archive "$TMP_ROOT/$FILE"
  install_update_command
  install_local_copy
  setup_path

  local final
  final="$("$GO_BIN" version 2>/dev/null || printf '%s' "$TARGET_VERSION")"
  printf '\n'
  ok "Listo: $final"
  if [ "$SETUP_PATH" -eq 1 ]; then
    printf '    Abre una terminal nueva o ejecuta: source %s/.bashrc\n' "$TARGET_HOME"
  fi
  printf '    Actualizar más adelante: %s\n' "$BIN_DIR/go-update"
  return "$EX_OK"
}

do_list() {
  resolve_target
  list_versions
  return "$EX_OK"
}

do_uninstall() {
  info "Se eliminará:"
  printf '    - %s\n' "$GO_DIR"
  printf '    - %s\n' "$BIN_DIR/go-update"
  printf '    - %s\n' "$LIB_DIR"
  if [ "$PREFIX" = "/usr/local" ]; then
    printf '    - /etc/profile.d/go.sh\n'
  fi
  printf '    - los bloques de PATH de %s/.{bashrc,profile,zshrc}\n' "$TARGET_HOME"

  if [ "$DRY_RUN" -eq 0 ]; then
    if ! confirm "¿Desinstalar Go de $PREFIX?"; then
      die "Cancelado."
    fi
  fi

  setup_sudo

  if [ "$DRY_RUN" -eq 1 ]; then
    skip "[dry-run] sin cambios en el sistema."
    return "$EX_OK"
  fi

  if [ -e "$GO_DIR" ]; then
    as_root rm -rf -- "$GO_DIR"
    ok "Eliminado $GO_DIR"
  fi
  if [ -e "$BIN_DIR/go-update" ]; then
    as_root rm -f -- "$BIN_DIR/go-update"
    ok "Eliminado $BIN_DIR/go-update"
  fi
  if [ -e "$LIB_DIR" ]; then
    as_root rm -rf -- "$LIB_DIR"
    ok "Eliminado $LIB_DIR"
  fi
  if [ "$PREFIX" = "/usr/local" ] && [ -e /etc/profile.d/go.sh ]; then
    as_root rm -f -- /etc/profile.d/go.sh
    ok "Eliminado /etc/profile.d/go.sh"
  fi

  # Elimina directorios auxiliares que hayan quedado vacíos (rmdir solo
  # borra directorios vacíos; /usr/local/bin nunca se ve afectado).
  as_root rmdir "$BIN_DIR" 2>/dev/null || true
  as_root rmdir "$LIB_DIR" 2>/dev/null || true
  as_root rmdir "$(dirname "$LIB_DIR")" 2>/dev/null || true

  local rc
  for rc in "$TARGET_HOME/.bashrc" "$TARGET_HOME/.profile" "$TARGET_HOME/.zshrc"; do
    remove_rc_block "$rc"
  done

  ok "Desinstalación completa. Abre una terminal nueva para refrescar el PATH."
  return "$EX_OK"
}

# ---------------------------------------------------------------------------
# Programa principal
# ---------------------------------------------------------------------------
main() {
  local rc=0
  parse_args "$@"
  derive_paths
  assert_safe_paths
  preflight
  init_tmp

  case "$MODE" in
    list)
      resolve_target
      do_list || rc=$?
      ;;
    check)
      resolve_target
      do_check || rc=$?
      ;;
    uninstall)
      do_uninstall || rc=$?
      ;;
    install)
      resolve_target
      do_install || rc=$?
      ;;
    *)
      die "Modo desconocido: $MODE"
      ;;
  esac
  exit "$rc"
}

if [ "${BASH_SOURCE[0]:-}" = "$0" ] || [ -z "${BASH_SOURCE[0]:-}" ]; then
  main "$@"
fi
