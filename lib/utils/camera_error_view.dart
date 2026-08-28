// lib/utils/camera_error_view.dart
//
// Estado de error reutilizable para MobileScanner (fix post-build, Parte
// 12). Reemplaza el ícono mudo por defecto del paquete `mobile_scanner`
// —que se ve como un simple "!" blanco sin texto ni forma de
// reintentar— por una pantalla que muestra el motivo real y dos acciones:
// reintentar, y copiar el detalle técnico completo (incluye el stack
// trace nativo si el plugin lo entregó) para poder reportarlo.
//
// La usan tanto ScannerHomeScreen (Parte 2) como BarcodeScannerScreen
// (Parte 4/5) para no repetir el mismo bloque dos veces.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

/// Mensaje corto a mostrar en pantalla.
///
/// `MobileScannerErrorCode` en mobile_scanner 5.2.3 (la versión que usa
/// este proyecto) todavía no trae un getter `.message` con texto legible
/// (eso llegó en una versión posterior del paquete) — usamos el detalle
/// nativo si vino alguno y, si no, el nombre del código de error.
String cameraErrorShortMessage(MobileScannerException error) {
  final detail = error.errorDetails?.message;
  if (detail != null && detail.trim().isNotEmpty) return detail;
  return 'Código de error: ${error.errorCode.name}';
}

/// Texto completo para copiar/reportar: código de error + mensaje +
/// stack trace nativo (`errorDetails.details`), si el plugin lo entregó.
String cameraErrorFullDetails(MobileScannerException error) {
  final buffer = StringBuffer('errorCode: ${error.errorCode.name}');
  final message = error.errorDetails?.message;
  if (message != null && message.trim().isNotEmpty) {
    buffer.write('\nmessage: $message');
  }
  final details = error.errorDetails?.details;
  if (details != null) {
    final detailsText = details.toString();
    if (detailsText.trim().isNotEmpty) {
      buffer.write('\ndetails:\n$detailsText');
    }
  }
  return buffer.toString();
}

class CameraErrorView extends StatelessWidget {
  final MobileScannerException error;
  final VoidCallback onRetry;
  final VoidCallback? onFallback;
  final String fallbackLabel;

  const CameraErrorView({
    super.key,
    required this.error,
    required this.onRetry,
    this.onFallback,
    this.fallbackLabel = 'Seguir sin cámara',
  });

  Future<void> _copyDetails(BuildContext context) async {
    await Clipboard.setData(ClipboardData(text: cameraErrorFullDetails(error)));
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Detalle técnico copiado')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Colors.black,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.videocam_off_outlined, size: 56, color: Colors.white38),
              const SizedBox(height: 16),
              const Text(
                'No se pudo abrir la cámara',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
              ),
              const SizedBox(height: 8),
              Text(
                cameraErrorShortMessage(error),
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white70, fontSize: 13),
              ),
              const SizedBox(height: 18),
              ElevatedButton(onPressed: onRetry, child: const Text('Reintentar')),
              if (onFallback != null) ...[
                const SizedBox(height: 8),
                TextButton(onPressed: onFallback, child: Text(fallbackLabel)),
              ],
              const SizedBox(height: 4),
              TextButton(
                onPressed: () => _copyDetails(context),
                style: TextButton.styleFrom(foregroundColor: Colors.white38),
                child: const Text('Copiar detalle técnico', style: TextStyle(fontSize: 12)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
