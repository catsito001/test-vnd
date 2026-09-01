#!/usr/bin/env python3
"""
Parte 12 — Inserta los <uses-permission>/<uses-feature> de cámara y
Bluetooth, y fija el nombre visible de la app (android:label), en el
AndroidManifest.xml recién generado por `flutter create` (ver
.github/workflows/build-apk.yml). Se ejecuta como un paso más del build en
GitHub Actions, así no hay que editar el manifest a mano cada vez que se
regenera el proyecto Android.
"""

import re

PATH = "android/app/src/main/AndroidManifest.xml"

# Nombre visible de la app (el que se ve bajo el ícono, en "apps
# recientes", etc). `flutter create --project-name vende_movil` deja acá
# el nombre del proyecto Dart tal cual ("vende_movil"), así que siempre lo
# pisamos con el nombre real de la app.
APP_LABEL = "Ventas Cell"

PERMISSIONS_BLOCK = """
    <uses-permission android:name="android.permission.CAMERA" />
    <uses-permission android:name="android.permission.BLUETOOTH" android:maxSdkVersion="30" />
    <uses-permission android:name="android.permission.BLUETOOTH_ADMIN" android:maxSdkVersion="30" />
    <uses-permission android:name="android.permission.BLUETOOTH_CONNECT" />
    <uses-permission android:name="android.permission.BLUETOOTH_SCAN" android:usesPermissionFlags="neverForLocation" />
    <uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" android:maxSdkVersion="30" />
    <uses-feature android:name="android.hardware.camera" android:required="false" />
    <uses-feature android:name="android.hardware.camera.autofocus" android:required="false" />
    <uses-feature android:name="android.hardware.bluetooth" android:required="false" />

"""


def main() -> None:
    with open(PATH, encoding="utf-8") as f:
        manifest = f.read()

    # 1) Nombre visible de la app. Se pisa siempre (es idempotente: correr
    #    esto dos veces deja el mismo resultado), sin importar si los
    #    permisos ya estaban insertados o no.
    manifest, label_replaced = re.subn(
        r'android:label="[^"]*"', f'android:label="{APP_LABEL}"', manifest, count=1
    )
    if not label_replaced:
        print(f"Aviso: no se encontró android:label en {PATH}; no se pudo fijar el nombre de la app.")

    # 2) Permisos de cámara/Bluetooth (solo si todavía no están).
    if "android.permission.CAMERA" in manifest:
        print("El manifest ya tenía los permisos, no se tocan de nuevo.")
    else:
        if "    <application" not in manifest:
            raise SystemExit(
                f"No se encontró '<application' en {PATH}; revisa si "
                "`flutter create` cambió el formato del manifest."
            )
        manifest = manifest.replace("    <application", PERMISSIONS_BLOCK + "    <application", 1)
        print("Permisos insertados en", PATH)

    with open(PATH, "w", encoding="utf-8") as f:
        f.write(manifest)
    print(f'Nombre de la app fijado a "{APP_LABEL}" en {PATH}.')


if __name__ == "__main__":
    main()
