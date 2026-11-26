<p align="center">
  <img src="../screenshots/smart-care-dark.png" alt="Sift" width="760">
</p>

<p align="center">
  <a href="../README.md">English</a> |
  <a href="README.ar.md">العربية</a> |
  <b>Español</b> |
  <a href="README.ja.md">日本語</a> |
  <a href="README.pt-BR.md">Português (Brasil)</a> |
  <a href="README.zh-Hans.md">简体中文</a> |
  <a href="README.zh-Hant.md">繁體中文</a>
</p>

<h1 align="center">Sift</h1>

<p align="center">
  <b>Recupera tu Mac.</b><br>
  Cuidado para Mac gratuito y de código abierto: limpieza, gestión de apps, exploración del almacenamiento y revisiones del sistema. Sin suscripción ni telemetría.
</p>

> Este es un resumen. El [README en inglés](../README.md) es la referencia completa y actualizada.

## Si vienes de PureMac

Sift empezó como un fork de PureMac, el limpiador de código abierto de Moamen Basel, y ahora se desarrolla de forma independiente. En el primer arranque copia tus ajustes e historial de PureMac; los datos antiguos no se tocan. Concede de nuevo el **acceso total al disco**, porque el permiso pertenece al identificador anterior. La herramienta de terminal ahora se llama `sift-cli`.

## Instalación

Descarga `Sift-4.1.1.dmg` desde la [última versión](https://github.com/BadryansahBangsawan/Sift/releases/latest) y arrastra Sift a Aplicaciones.

Esta versión aún no está notarizada por Apple, así que macOS la detiene la primera vez:

1. Abre Sift. macOS dice que no puede verificar la app; pulsa **Listo**.
2. Abre **Ajustes del Sistema > Privacidad y seguridad**, desplázate y pulsa **Abrir igualmente** junto a Sift.
3. Concede el **acceso total al disco** cuando Sift lo pida.

### Compilar desde el código fuente

```bash
brew install xcodegen
git clone https://github.com/BadryansahBangsawan/Sift.git
cd Sift
xcodegen generate
xcodebuild -project Sift.xcodeproj -scheme Sift -configuration Release \
  -derivedDataPath build build
open build/Build/Products/Release/Sift.app
```

### Línea de comandos

```bash
cd cli
swift build -c release
.build/release/sift-cli
```

## Qué hace

- **Resumen**: medidor de almacenamiento, dónde está la basura, las mayores ganancias, batería y elementos de arranque.
- **Limpieza**: basura del sistema, herramientas de IA, cachés de desarrollo, instaladores, archivos grandes y antiguos, archivos de Mail y Papelera, con filtros, exclusiones y una revisión antes de eliminar nada.
- **Herramientas de IA**: cachés y registros de Claude, Claude Code, ChatGPT, Cursor, Ollama y similares. El historial de chats y sesiones aparece pero nunca se preselecciona y va a la Papelera; las carpetas de memoria, los ajustes y las credenciales nunca se tocan.
- **Basura de proyectos**: `node_modules`, `.venv`, `target`, `.build` y carpetas similares en las carpetas de proyectos que elijas, solo cuando Sift puede demostrar que son generadas y git las ignora. Van a la Papelera y nunca forman parte de la limpieza programada.
- **Apple Intelligence**: desactívala función por función, elimina sus modelos en el dispositivo y bloquea su descarga con un perfil que tú apruebas. Cada cambio se revisa antes y se puede deshacer (Apple silicon, macOS 15.1 o posterior).
- **Desinstalador y restos**: encuentra los archivos relacionados de una app y los restos de apps eliminadas; revisa y mueve a la Papelera.
- **Explorador de espacio, duplicados y fotos similares**, **Protección** y **Rendimiento**.
- **Limpieza programada** (semanal con día y hora), 13 idiomas, apariencia clara/oscura y color de acento.

## Privacidad y seguridad

Sin telemetría, analíticas ni informes de fallos. Los análisis son locales y funcionan sin conexión. Todo se revisa antes de eliminarse; algunas limpiezas (categorías) borran de forma permanente, así que lee la confirmación. Sift necesita **acceso total al disco** para analizar ubicaciones protegidas; la configuración inicial te guía.

## Créditos

Basado en [PureMac](https://github.com/momenbasel/PureMac) de Moamen Basel y sus colaboradores. La herramienta de Apple Intelligence está portada de [RemoveMacAI](https://github.com/omlahore/RemoveMacAI) de Om Lahore, que se basa en [pared](https://github.com/4evy/pared) de 4evy. Todos con licencia MIT; consulta [THIRD-PARTY-NOTICES.md](../THIRD-PARTY-NOTICES.md).

## Licencia

MIT. Consulta [LICENSE](../LICENSE).
