// lib/utils/permissions.dart
//
// Parte 12 — Permisos en tiempo de ejecución.
//
// Declarar los permisos en AndroidManifest.xml es necesario pero no
// suficiente: desde Android 6.0 hay que pedirlos también en tiempo de
// ejecución antes de usar la cámara o el Bluetooth, y mostrar un diálogo
// explicativo si el usuario los rechaza (tal como pide la Parte 12 del
// prompt). Este archivo centraliza esa lógica para que la pida siempre de
// la misma forma, en vez de repetirla en cada pantalla:
//   - `ensureCameraPermission`: usado por ScannerHomeScreen (Parte 2) y
//     BarcodeScannerScreen (Parte 4/5) antes de encender la cámara.
//   - `ensureBluetoothPermissions`: usado por SettingsScreen (Parte 10) al
//     buscar impresoras, y por `printing.dart` (Parte 8) al imprimir.

import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

/// Pide el permiso de cámara. Muestra un diálogo explicativo antes de
/// pedirlo la primera vez, y uno distinto (ofreciendo abrir Ajustes) si el
/// usuario ya lo rechazó permanentemente. Devuelve `true` solo si el
/// permiso queda concedido.
Future<bool> ensureCameraPermission(BuildContext context) async {
  var status = await Permission.camera.status;
  if (status.isGranted) return true;

  if (status.isPermanentlyDenied) {
    if (!context.mounted) return false;
    await _showSettingsDialog(
      context,
      title: 'Cámara desactivada',
      message: 'Vende Móvil necesita la cámara para escanear los códigos de '
          'barra de tus productos. Actívala desde los Ajustes del sistema.',
    );
    return false;
  }

  if (!context.mounted) return false;
  final shouldAsk = await _showRationaleDialog(
    context,
    title: 'Permiso de cámara',
    message: 'Vende Móvil usa la cámara para leer los códigos de barra y '
        'armar el carrito de venta automáticamente. También puedes agregar '
        'productos a mano si prefieres no darlo.',
  );
  if (!shouldAsk) return false;

  status = await Permission.camera.request();
  if (status.isPermanentlyDenied && context.mounted) {
    await _showSettingsDialog(
      context,
      title: 'Cámara desactivada',
      message: 'Puedes activar el permiso de cámara cuando quieras desde '
          'los Ajustes del sistema.',
    );
  }
  return status.isGranted;
}

/// Pide los permisos de Bluetooth clásico necesarios para buscar e
/// imprimir en la impresora térmica: BLUETOOTH_CONNECT/BLUETOOTH_SCAN en
/// Android 12+, y ubicación en versiones anteriores (algunos paquetes de
/// Bluetooth clásico la necesitan para poder escanear dispositivos).
///
/// [context] puede ser `null` (por ejemplo al imprimir un ticket justo
/// después de confirmar una venta, donde no conviene interrumpir con un
/// diálogo): en ese caso simplemente se piden los permisos sin mostrar
/// explicación previa. Pasa `showRationale: false` para el mismo efecto
/// incluso teniendo contexto disponible.
Future<bool> ensureBluetoothPermissions(
  BuildContext? context, {
  bool showRationale = true,
}) async {
  const permissions = [
    Permission.bluetoothConnect,
    Permission.bluetoothScan,
    Permission.location,
  ];

  final current = await Future.wait(permissions.map((p) => p.status));
  if (current.every((s) => s.isGranted || s.isLimited)) return true;

  if (showRationale && context != null && context.mounted) {
    final shouldAsk = await _showRationaleDialog(
      context,
      title: 'Permiso de Bluetooth',
      message: 'Vende Móvil necesita Bluetooth para buscar tu impresora '
          'térmica y enviarle el ticket de venta.',
    );
    if (!shouldAsk) return false;
  }

  final statuses = await permissions.request();
  final granted = statuses.values.every((s) => s.isGranted || s.isLimited);

  if (!granted &&
      statuses.values.any((s) => s.isPermanentlyDenied) &&
      context != null &&
      context.mounted) {
    await _showSettingsDialog(
      context,
      title: 'Bluetooth desactivado',
      message: 'Activa los permisos de Bluetooth desde los Ajustes del '
          'sistema para poder conectar la impresora.',
    );
  }
  return granted;
}

// ---------------------------------------------------------------------
// Diálogos reutilizables
// ---------------------------------------------------------------------

Future<bool> _showRationaleDialog(
  BuildContext context, {
  required String title,
  required String message,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: const Text('Ahora no'),
        ),
        ElevatedButton(
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: const Text('Continuar'),
        ),
      ],
    ),
  );
  return result ?? false;
}

Future<void> _showSettingsDialog(
  BuildContext context, {
  required String title,
  required String message,
}) {
  return showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: const Text('Ahora no'),
        ),
        ElevatedButton(
          onPressed: () {
            Navigator.of(dialogContext).pop();
            openAppSettings();
          },
          child: const Text('Abrir Ajustes'),
        ),
      ],
    ),
  );
}
