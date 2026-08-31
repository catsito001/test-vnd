# Cómo probar Vende Móvil sin instalar Android Studio

La compilación entera pasa en los servidores de GitHub (gratis e ilimitado
en repos públicos). Tú solo subes archivos, esperas unos minutos y bajas un
`.apk` para instalarlo en tu celular. No necesitas instalar Flutter, el SDK
de Android, ni nada pesado en tu computadora.

Ya te dejé listo `.github/workflows/build-apk.yml`: arma un proyecto
Android completo (el `flutter create` que le faltaba a este repo), le mete
los permisos de cámara/Bluetooth de la Parte 12, y te entrega el `.apk`
como descarga. No necesitas entender ese archivo para usarlo.

## 1. Crear el repositorio

1. Entra a [github.com/new](https://github.com/new), crea un repo **público**
   (así las Actions son gratis sin límite de minutos) — por ejemplo
   `vende-movil`.
2. No marques "Add a README" (para que quede vacío y no choque con nada).

## 2. Subir el proyecto

**Sin usar la terminal:** en la página del repo recién creado, click en
**"uploading an existing file"**. Desde tu explorador de archivos,
selecciona **todo el contenido de la carpeta descomprimida** (`lib/`,
`android/`, `scripts/`, `.github/`, `pubspec.yaml`, etc. — todo junto, no
carpeta por carpeta) y arrástralo a la página. Los navegadores basados en
Chrome/Edge conservan la estructura de carpetas al arrastrar. Escribe un
mensaje de commit abajo y dale a **"Commit changes"**.

> Si el navegador no te deja arrastrar carpetas completas, sube primero
> `pubspec.yaml`, `README_estructura.md`, etc., y para las carpetas usa
> "Add file → Create new file" escribiendo la ruta completa en el nombre,
> por ejemplo `lib/main.dart`, `lib/screens/home_screen.dart`, etc. — GitHub
> crea las carpetas solo con escribir la ruta. Es más lento pero funciona
> sin ninguna herramienta instalada.

**Con git instalado** (si lo tienes, es más rápido):
```bash
cd vende_movil
git init
git add .
git commit -m "Proyecto inicial"
git branch -M main
git remote add origin https://github.com/TU_USUARIO/vende-movil.git
git push -u origin main
```

## 3. Ver la compilación

1. En GitHub, abre la pestaña **"Actions"** de tu repo.
2. Al hacer el primer push (o commit) ya debería aparecer un run llamado
   **"Build APK"** corriendo solo. Si no aparece, click en **"Run
   workflow"** manualmente.
3. La primera corrida tarda entre 5 y 10 minutos (descarga Flutter y las
   dependencias). Las siguientes son más rápidas gracias al caché.
4. Si algo falla, click en el run en rojo y revisa el paso que reventó —
   casi siempre es un error de sintaxis en algún `.dart` que se puede leer
   directo en el log.

## 4. Descargar el APK

1. Click en el run que terminó en verde (✅).
2. Abajo del todo, en la sección **"Artifacts"**, vas a ver
   `vende-movil-apk` — descárgalo (es un `.zip` que trae adentro
   `app-release.apk`).
3. Descomprímelo.

## 5. Instalarlo en tu celular

1. Pasa el `.apk` a tu Android por el medio que te resulte más cómodo:
   cable USB, subirlo a Google Drive y descargarlo desde el celular,
   mandártelo por WhatsApp/Telegram a ti mismo, etc.
2. Al abrir el archivo, Android va a pedirte permiso para **"instalar apps
   de orígenes desconocidos"** para esa app (Drive, WhatsApp, el explorador
   de archivos, la que hayas usado) — actívalo solo para esa vez.
3. Toca **Instalar**. Listo, ya tienes Vende Móvil funcionando de verdad en
   tu teléfono: cámara, carrito, inventario, checkout, historial y ajustes.

### Sobre la impresora térmica

Todo el resto de la app se prueba sin nada adicional. Para probar la
**impresión** (Parte 8) necesitas tener a mano una impresora térmica
Bluetooth real ya emparejada con el celular desde Ajustes de Android —
sin eso, el botón de imprimir simplemente va a avisar que no hay
impresora configurada (comportamiento esperado, no es un bug).

## Si más adelante quieres compilar en tu propia compu

No hace falta Android Studio completo — alcanza con:

1. El SDK de Flutter (se descarga como un .zip, se descomprime en
   cualquier carpeta, sin instalador): https://docs.flutter.dev/get-started/install
2. Solo las **"command line tools"** de Android (no el Android Studio
   entero): https://developer.android.com/studio#command-tools — con eso
   alcanza para compilar, no hace falta el emulador ni la IDE.
3. `flutter doctor --android-licenses` para aceptar licencias.
4. En una carpeta vacía: `flutter create --platforms=android vende_movil`,
   y ahí reemplaza el `lib/` generado por el de este proyecto, copia nuestro
   `pubspec.yaml`, y pega el bloque de permisos de
   `android/app/src/main/AndroidManifest.xml` (el que ya viene en este
   repo) dentro del manifest recién generado, justo antes de
   `<application`.
5. `flutter pub get` y `flutter build apk --release`.

Esto pesa bastante menos que Android Studio completo (que trae emulador,
IDE gráfica, etc.), pero si tu prioridad es cero instalación, el camino de
GitHub Actions de arriba es el más simple.
