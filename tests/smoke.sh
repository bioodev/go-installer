#!/usr/bin/env bash
#
# smoke.sh — pruebas básicas del instalador go-installer.
# Uso:  ./tests/smoke.sh [--skip-download]
# Requiere red (API de go.dev). Las instalaciones se hacen en un directorio
# temporal y con un HOME ficticio; no toca el sistema real.
#
set -Eeuo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
INSTALLER="$HERE/install.sh"

PASS=0
FAIL=0
SKIP_DOWNLOAD=0

[ "${1:-}" = "--skip-download" ] && SKIP_DOWNLOAD=1

note() { printf '\n== %s\n' "$*"; }

check() {
  if [ "$1" = "$2" ]; then
    PASS=$((PASS + 1)); printf '  ok  %s\n' "$3"
  else
    FAIL=$((FAIL + 1)); printf '  *** FALLO: %s (esperado %s, obtenido %s)\n' "$3" "$2" "$1"
  fi
}

assert_true() {
  local desc="$1"
  shift
  if "$@"; then
    PASS=$((PASS + 1)); printf '  ok  %s\n' "$desc"
  else
    FAIL=$((FAIL + 1)); printf '  *** FALLO: %s\n' "$desc"
  fi
}

SANDBOX="$(mktemp -d /tmp/smoke.XXXXXX)"
FAKE_HOME="$SANDBOX/home"
PREFIX="$SANDBOX/prefix"
trap 'rm -rf -- "$SANDBOX"' EXIT

mkdir -p "$FAKE_HOME"
: > "$FAKE_HOME/.bashrc"
: > "$FAKE_HOME/.profile"
: > "$FAKE_HOME/.zshrc"

COMMON=(GO_INSTALL_PREFIX="$PREFIX" GO_INSTALLER_TARGET_HOME="$FAKE_HOME")

note "--version"
out="$(bash "$INSTALLER" --version)"
check "$out" "go-installer 1.0.0" "--version"

note "--help"
# shellcheck disable=SC2016  # $1 se expande dentro de bash -c
assert_true "--help termina bien" bash -c 'bash "$1" --help >/dev/null' _ "$INSTALLER"

note "--list (últimas versiones)"
out="$(bash "$INSTALLER" --list)"
check $? 0 "--list"
assert_true "--list muestra versiones" grep -q "go1\." <<< "$out"

note "--check en prefijo vacío (10 = actualización disponible)"
rc=0; bash "$INSTALLER" --check >/dev/null 2>&1 || rc=$?
check "$rc" 10 "--check sin instalar"

note "--go-version inexistente (debe fallar)"
rc=0; env "${COMMON[@]}" bash "$INSTALLER" --go-version 9.9.9 --check >/dev/null 2>&1 || rc=$?
check "$rc" 1 "--go-version 9.9.9 rechazado"

note "--dry-run (no descarga, no escribe)"
out="$(env "${COMMON[@]}" bash "$INSTALLER" --dry-run)"
check $? 0 "--dry-run"
assert_true "--dry-run muestra el plan" grep -q "\[dry-run\]" <<< "$out"
check "$(find "$PREFIX" -mindepth 1 2>/dev/null | wc -l)" 0 "--dry-run no crea el prefijo"
check "$(grep -cE "# (>>>|<<<) go-installer" "$FAKE_HOME/.bashrc" 2>/dev/null || true)" 0 "--dry-run no toca el .bashrc"

if [ "$SKIP_DOWNLOAD" -eq 0 ]; then
  note "instalación completa en prefijo temporal"
  env "${COMMON[@]}" bash "$INSTALLER" >/dev/null
  check $? 0 "instalación"
  assert_true "existe $PREFIX/go/bin/go" test -x "$PREFIX/go/bin/go"
  assert_true "go version ejecuta" "$PREFIX/go/bin/go" version
  assert_true "existe $PREFIX/bin/go-update" test -x "$PREFIX/bin/go-update"
  assert_true "existe la copia local del instalador" test -r "$PREFIX/lib/go-installer/install.sh"
  check "$(grep -cE "# (>>>|<<<) go-installer" "$FAKE_HOME/.bashrc" 2>/dev/null || true)" 2 ".bashrc con marcadores del bloque"

  note "idempotencia (segunda ejecución)"
  out="$(env "${COMMON[@]}" bash "$INSTALLER")"
  assert_true "segunda ejecución no reinstala" grep -q "ya está en la última versión" <<< "$out"

  note "go-update --check (usa la copia del instalador vía file://)"
  rc=0
  GO_INSTALLER_RAW_BASE="file://$HERE" "$PREFIX/bin/go-update" --check >/dev/null 2>&1 || rc=$?
  check "$rc" 10 "go-update --check reporta actualización"

  note "fijar versión más antigua (--go-version)"
  env "${COMMON[@]}" bash "$INSTALLER" --go-version 1.26.3 >/dev/null
  check "$("$PREFIX/go/bin/go" version 2>/dev/null | awk '{print $3}')" go1.26.3 "se instaló go1.26.3"

  note "volver a la última versión"
  env "${COMMON[@]}" bash "$INSTALLER" >/dev/null
  out="$("$PREFIX/go/bin/go" version | awk '{print $3}')"
  assert_true "se restauró la última versión ($out)" test "$out" != go1.26.3

  note "desinstalación (--uninstall --yes)"
  env "${COMMON[@]}" bash "$INSTALLER" --uninstall --yes >/dev/null
  check $? 0 "--uninstall"
  check "$(find "$PREFIX" -mindepth 1 2>/dev/null | wc -l)" 0 "prefijo vacío tras desinstalar"
  check "$(grep -cE "# (>>>|<<<) go-installer" "$FAKE_HOME/.bashrc" 2>/dev/null || true)" 0 ".bashrc limpio"
else
  note "descargas omitidas (--skip-download)"
fi

printf '\nRESULTADO: %s ok, %s fallos\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]