// lib/utils/utils.dart
//
// Utilidades pequeñas y reutilizables en varias pantallas:
// - formatCurrency: formatea montos como "S/ 0.00" (Parte 11).
// - persistPickedImage: copia una foto elegida con image_picker a un
//   directorio local permanente (Partes 5 y 10 la usan para fotos de
//   producto y para el QR de Yape).

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

final NumberFormat _currencyFormat = NumberFormat.currency(
  locale: 'es_PE',
  symbol: 'S/ ',
  decimalDigits: 2,
);

String formatCurrency(num amount) => _currencyFormat.format(amount);

/// Sonido corto de feedback al tocar "+"/"-" para cambiar la cantidad de
/// un producto en el carrito (Parte 13). Usa el sonido de sistema de
/// Android en vez de un paquete de audio o un archivo de sonido extra:
/// no hace falta declarar ningún asset y respeta el ajuste "Sonidos
/// táctiles" del propio teléfono (Ajustes > Sonido).
void playQuantityChangeSound() {
  SystemSound.play(SystemSoundType.click);
}

/// Copia el archivo elegido (cámara o galería) al directorio de documentos
/// de la app y devuelve la ruta permanente. `image_picker` a veces entrega
/// un archivo en una carpeta temporal/caché que el sistema puede borrar,
/// así que conviene guardar una copia propia antes de guardar la ruta en
/// SQLite.
Future<String?> persistPickedImage(XFile file, {String prefix = 'img'}) async {
  try {
    final docsDir = await getApplicationDocumentsDirectory();
    final ext = p.extension(file.path).isEmpty ? '.jpg' : p.extension(file.path);
    final fileName = '${prefix}_${DateTime.now().millisecondsSinceEpoch}$ext';
    final savedPath = p.join(docsDir.path, fileName);
    await File(file.path).copy(savedPath);
    return savedPath;
  } catch (_) {
    return null;
  }
}
