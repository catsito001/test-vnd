#!/usr/bin/env python3
"""
Fuerza `compileSdk = 36` en el android/app/build.gradle(.kts) recién
generado por `flutter create` (ver .github/workflows/build-apk.yml), en
vez de dejar el `flutter.compileSdkVersion` que trae la plantilla.

Nota: la causa de fondo del error "file_picker is currently compiled
against android-34" NO era esto (era que file_picker < 10.3.3 traía su
propio compileSdk fijo y bajo en su build.gradle, arreglado subiendo la
versión del paquete en pubspec.yaml). Este script se deja de todas formas
porque fijar el compileSdk de la propia app a un valor moderno sigue
siendo una buena práctica en general.

Es un reemplazo de texto simple (no un parser de Gradle): si en algún
momento `flutter.compileSdkVersion` ya no aparece en el archivo (porque
Flutter subió su propio default, o cambió el formato de la plantilla), el
script no encuentra nada que tocar y no hace nada.
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
        else:
            print(f"{path} no tiene 'flutter.compileSdkVersion'; no se tocó.")
        return

    print("No se encontró android/app/build.gradle(.kts); no se tocó nada.")


if __name__ == "__main__":
    main()
