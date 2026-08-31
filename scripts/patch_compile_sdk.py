#!/usr/bin/env python3
"""
Fuerza compileSdk = 36 tanto en la app como en CADA plugin (ej.
file_picker, mobile_scanner...), en el proyecto Android recién generado
por `flutter create` (ver .github/workflows/build-apk.yml).

Por qué hacen falta DOS parches:

1. android/app/build.gradle.kts (la app): usa `compileSdk =
   flutter.compileSdkVersion`, un valor que trae hardcodeado el propio SDK
   de Flutter instalado. Lo pisamos por un literal 36 acá.

2. android/build.gradle.kts (la raíz): cada plugin con código nativo (ej.
   file_picker) se agrega al build como un subproyecto Gradle CON SU
   PROPIO build.gradle — un archivo que vive adentro del paquete del
   plugin en pub-cache, no algo que este repo controle. Si ESE build.gradle
   trae su propio compileSdk fijo y bajo (no depende de qué Flutter esté
   instalado), pisar solo el de la app no alcanza: sigue fallando con
   "requires... compile against version 36... currently compiled against
   android-34", pero ahora apuntando al plugin (":file_picker is currently
   compiled against android-34") en vez de a la app. La solución estándar
   es un bloque `subprojects { }` en la RAÍZ que pisa el compileSdk de
   cada subproyecto Android después de que su propio plugin ya se aplicó.

Ambos parches son idempotentes (buscan su propio marcador / el texto
exacto a reemplazar), así que no hay problema en correr el script de
nuevo o en que en el futuro deje de hacer falta.
"""

MIN_COMPILE_SDK = 36

APP_GRADLE_PATHS = [
    "android/app/build.gradle.kts",
    "android/app/build.gradle",
]

ROOT_GRADLE_PATH = "android/build.gradle.kts"

ROOT_PATCH_MARKER = "// >>> patch_compile_sdk.py: fuerza compileSdk en los plugins"

ROOT_PATCH_BLOCK = f"""
{ROOT_PATCH_MARKER}
// file_picker (via flutter_plugin_android_lifecycle) ya pide compileSdk
// >= 36. Cada plugin trae su PROPIO build.gradle (no es parte de este
// repo), así que la única forma de subirles el compileSdk a todos es
// pisarlo acá, a nivel raíz, para cada subproyecto Android.
subprojects {{
    plugins.withId("com.android.library") {{
        extensions.configure<com.android.build.gradle.LibraryExtension> {{
            if ((compileSdk ?: 0) < {MIN_COMPILE_SDK}) {{
                compileSdk = {MIN_COMPILE_SDK}
            }}
        }}
    }}
}}
"""


def patch_app_gradle() -> None:
    for path in APP_GRADLE_PATHS:
        try:
            with open(path, encoding="utf-8") as f:
                content = f.read()
        except FileNotFoundError:
            continue

        replaced = content.replace("flutter.compileSdkVersion", str(MIN_COMPILE_SDK))
        if replaced != content:
            with open(path, "w", encoding="utf-8") as f:
                f.write(replaced)
            print(f"[app] compileSdk fijado a {MIN_COMPILE_SDK} en {path}.")
        else:
            print(f"[app] {path} no tiene 'flutter.compileSdkVersion'; no se tocó.")
        return

    print("[app] No se encontró android/app/build.gradle(.kts); no se tocó nada.")


def patch_root_gradle() -> None:
    try:
        with open(ROOT_GRADLE_PATH, encoding="utf-8") as f:
            content = f.read()
    except FileNotFoundError:
        print(f"[plugins] No se encontró {ROOT_GRADLE_PATH}; no se tocó nada.")
        return

    if ROOT_PATCH_MARKER in content:
        print("[plugins] El parche de compileSdk para plugins ya estaba aplicado; no se tocó de nuevo.")
        return

    with open(ROOT_GRADLE_PATH, "a", encoding="utf-8") as f:
        f.write(ROOT_PATCH_BLOCK)
    print(f"[plugins] Agregado bloque subprojects{{}} para forzar compileSdk {MIN_COMPILE_SDK} en {ROOT_GRADLE_PATH}.")


def main() -> None:
    patch_app_gradle()
    patch_root_gradle()


if __name__ == "__main__":
    main()
