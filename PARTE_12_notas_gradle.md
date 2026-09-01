# Parte 12 — Checklist de `android/app/build.gradle`

No tenía el `build.gradle` de tu proyecto entre los archivos subidos (solo
`.dart` + `pubspec.yaml`), así que en vez de inventarlo entero te dejo lo
puntual que hay que revisar para que el `AndroidManifest.xml` nuevo
funcione bien. Esto aplica tanto si tu proyecto usa `build.gradle` (Groovy)
como `build.gradle.kts` (Kotlin DSL, default en proyectos Flutter nuevos).

1. **`minSdkVersion` / `minSdk`**: `mobile_scanner` y `esc_pos_bluetooth`
   requieren **21 o más**. Si tu proyecto trae el default de
   `flutter.minSdkVersion`, ya cumple; si lo fijaste a mano, súbelo a 21+.

2. **`targetSdkVersion` / `targetSdk`**: usa el que trae `flutter create`
   por defecto (la versión estable más reciente del SDK de Android). Los
   permisos `BLUETOOTH_CONNECT` / `BLUETOOTH_SCAN` del manifest solo entran
   en efecto (reemplazando a `BLUETOOTH`/`BLUETOOTH_ADMIN`/ubicación) si el
   `targetSdk` es **31 o más** — con un `targetSdk` viejo, Android ignora
   esos permisos nuevos y sigue pidiendo los clásicos.

3. **`compileSdkVersion` / `compileSdk`**: debe ser igual o mayor al
   `targetSdk` de arriba. Con el default de `flutter.compileSdkVersion`
   alcanza. Si igual te sale un error de build tipo "requires... compile
   against version 36... currently compiled against android-34" apuntando
   a algún plugin puntual (no a tu app), no es la app: es que ESE plugin
   trae su propio `compileSdk` fijo y viejo en su propio `build.gradle`
   (nos pasó con `file_picker` antes de la 10.3.3 — lo arreglaron ahí
   mismo). La solución real es subir la versión de ese paquete en
   `pubspec.yaml`, no tocar el `compileSdk` de este proyecto.

4. No hace falta tocar nada más en Gradle para `permission_handler`: el
   plugin resuelve sus propios permisos nativos automáticamente al compilar
   (usa un manifest merge), siempre que los `<uses-permission>` estén
   declarados en tu `AndroidManifest.xml` como quedaron en el archivo nuevo.

Si tu `android/app/build.gradle(.kts)` ya usa
`minSdkVersion flutter.minSdkVersion` / `targetSdkVersion flutter.targetSdkVersion`
(el default de `flutter create`), no necesitas cambiar nada: ya cumple los
tres puntos de arriba.
