# Contexto

## Propósito

Instalar y mantener actualizado Go (golang) en Linux Mint y Ubuntu desde el
canal oficial de go.dev, con un único script invocable por
`curl ... | bash`, verificando siempre el checksum oficial antes de instalar.

## Audiencia

Usuarios de Linux Mint/Ubuntu que quieren Go actualizado sin PPA, Snap ni
gestores externos; y desarrolladores que quieren un instalador auditable y
reproducible (pueden fijar versión con `--go-version`).

## Alcance

**Incluye:**

- Instalación/actualización de la última versión estable (o una fijada).
- Verificación de SHA-256 contra el catálogo oficial antes de instalar.
- Configuración del PATH (sistema + usuario).
- Comando `go-update` para futuras actualizaciones.
- Desinstalación limpia.

**No incluye:**

- Gestión de múltiples versiones en paralelo (cada versión en su directorio).
- Desinstalación de Go instalado por otros medios (apt, snap, manual).
- Soporte para macOS/Windows (el script falla con un mensaje claro).
- Binarios de arquitecturas sin publicación oficial (compila desde fuente).

## Glosario

- **Prefijo** — directorio donde vive el árbol `go/` (defecto `/usr/local`).
- **`go-update`** — comando generado que re-ejecuta el instalador.
- **Catálogo** — JSON de `https://go.dev/dl/?mode=json&include=all` con las
  versiones publicadas y sus SHA-256.
- **Estable / previa** — `stable` / `rc` en el catálogo de go.dev.