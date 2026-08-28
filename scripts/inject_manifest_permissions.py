#!/usr/bin/env python3
"""
Parte 12 — Inserta los <uses-permission>/<uses-feature> de cámara y
Bluetooth en el AndroidManifest.xml recién generado por `flutter create`
(ver .github/workflows/build-apk.yml). Se ejecuta como un paso más del
build en GitHub Actions, así no hay que editar el manifest a mano cada vez
que se regenera el proyecto Android.
"""

PATH = "android/app/src/main/AndroidManifest.xml"

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

    if "android.permission.CAMERA" in manifest:
        print("El manifest ya tiene los permisos de Vende Móvil, no se toca.")
        return

    if "    <application" not in manifest:
        raise SystemExit(
            f"No se encontró '<application' en {PATH}; revisa si "
            "`flutter create` cambió el formato del manifest."
        )

    manifest = manifest.replace("    <application", PERMISSIONS_BLOCK + "    <application", 1)
    with open(PATH, "w", encoding="utf-8") as f:
        f.write(manifest)
    print("Permisos de Vende Móvil insertados en", PATH)


if __name__ == "__main__":
    main()
