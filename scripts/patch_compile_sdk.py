#!/usr/bin/env python3
"""
Fuerza `compileSdk = 36` en el android/app/build.gradle(.kts) recién
generado por `flutter create` (ver .github/workflows/build-apk.yml), en
vez de dejar el `flutter.compileSdkVersion` que trae la plantilla.

Hace falta porque `file_picker` (a través de su dependencia
`flutter_plugin_android_lifecycle`) ya pide compileSdk >= 36, y el
Flutter "stable" que usa el workflow puede traer un default más bajo
(compileSdk 34) hasta que el propio Flutter actualice su plantilla —
error típico: "requires ... compile against version 36 ... currently
compiled against android-34".

Es un reemplazo de texto simple (no un parser de Gradle), pensado para
durar hasta que Flutter suba su propio default: si en algún momento
`flutter.compileSdkVersion` ya no aparece en el archivo (porque Flutter
lo subió solo, o cambió el formato de la plantilla), el script no
encuentra nada que tocar y no hace nada — no rompe el build por las
dudas.
"""

MIN_COMPILE_SDK = 36

CANDIDATE_PATHS = [
    "android/app/build.gradle.kts",
    "android/app/build.gradle",
]


def main() -> None:
    for path in CANDIDATE_PATHS:
        try:
            with open(path, encoding="utf-8") as f:
                content = f.read()
        except FileNotFoundError:
            continue

        replaced = content.replace("flutter.compileSdkVersion", str(MIN_COMPILE_SDK))
        if replaced != content:
            with open(path, "w", encoding="utf-8") as f:
                f.write(replaced)
            print(f"compileSdk fijado a {MIN_COMPILE_SDK} en {path}.")
            return
        else:
            print(f"{path} no tiene 'flutter.compileSdkVersion' (¿ya está fijo, o cambió el formato?); no se tocó.")
            return

    print("No se encontró android/app/build.gradle(.kts); no se tocó nada.")


if __name__ == "__main__":
    main()
