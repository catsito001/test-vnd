// lib/utils/inventory_backup.dart
//
// Respaldo del inventario en un .zip (sección de Ajustes): exporta todos
// los productos, categorías y fotos a un único archivo que se comparte
// con el share sheet del sistema (Drive, WhatsApp, correo, etc.), para
// poder recuperarlo si hay que reinstalar la app, actualizarla, o pasarla
// a otro teléfono.
//
// Formato del .zip:
//   manifest.json      -> categorías y productos (ver _exportManifest)
//   photos/<archivo>    -> una copia de cada foto de producto
//
// El import hace MERGE, no reemplaza todo: si un producto ya existe (por
// código de barras, o por nombre exacto si no tiene código), lo actualiza
// en vez de duplicarlo. Las categorías se emparejan por nombre.

import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:cross_file/cross_file.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../data/database.dart';
import '../models/models.dart';

const _manifestFileName = 'manifest.json';
const _photosFolder = 'photos';

ArchiveFile? _findEntry(Archive archive, String name) {
  for (final f in archive) {
    if (f.name == name) return f;
  }
  return null;
}

/// Arma el zip (productos + categorías + fotos) y abre el share sheet del
/// sistema para guardarlo o enviarlo. Muestra un diálogo de carga mientras
/// arma el archivo.
Future<void> exportInventoryZip(BuildContext context) async {
  _showLoadingDialog(context, 'Preparando el respaldo...');
  try {
    final db = DatabaseHelper.instance;
    final categories = await db.getCategories();
    final products = await db.getProducts();
    final categoryNameById = {for (final c in categories) c.id: c.name};

    final archive = Archive();
    final productMaps = <Map<String, dynamic>>[];

    for (final product in products) {
      String? photoFile;
      if (product.photoPath != null && await File(product.photoPath!).exists()) {
        final bytes = await File(product.photoPath!).readAsBytes();
        photoFile = '$_photosFolder/${p.basename(product.photoPath!)}';
        archive.addFile(ArchiveFile(photoFile, bytes.length, bytes));
      }
      productMaps.add({
        'name': product.name,
        'description': product.description,
        'barcodes': product.barcodes,
        'categoryName': product.categoryId != null ? categoryNameById[product.categoryId] : null,
        'purchasePrice': product.purchasePrice,
        'salePrice': product.salePrice,
        'currentStock': product.currentStock,
        'minStock': product.minStock,
        'soldByWeight': product.soldByWeight,
        'photoFile': photoFile,
      });
    }

    final manifest = {
      'app': 'Ventas Cell',
      'exportedAt': DateTime.now().toIso8601String(),
      'categories': categories.map((c) => c.name).toList(),
      'products': productMaps,
    };
    final manifestBytes = utf8.encode(jsonEncode(manifest));
    archive.addFile(ArchiveFile(_manifestFileName, manifestBytes.length, manifestBytes));

    final zipBytes = ZipEncoder().encode(archive);
    if (zipBytes == null) throw Exception('No se pudo generar el zip');

    final tempDir = await getTemporaryDirectory();
    final stamp = DateTime.now().millisecondsSinceEpoch;
    final zipPath = p.join(tempDir.path, 'ventas_cell_inventario_$stamp.zip');
    await File(zipPath).writeAsBytes(zipBytes);

    if (!context.mounted) return;
    Navigator.of(context, rootNavigator: true).pop(); // cierra "Preparando..."

    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(zipPath)],
        text: 'Respaldo de inventario de Ventas Cell (${products.length} productos)',
      ),
    );
  } catch (e) {
    if (!context.mounted) return;
    Navigator.of(context, rootNavigator: true).pop();
    _showResultDialog(context, 'No se pudo exportar', 'Ocurrió un error armando el respaldo.\n\n$e');
  }
}

/// Deja elegir un .zip exportado antes y hace MERGE contra el inventario
/// actual. Muestra un resumen (nuevos / actualizados / fotos) al final.
Future<void> importInventoryZip(BuildContext context) async {
  final result = await FilePicker.platform.pickFiles(
    type: FileType.custom,
    allowedExtensions: ['zip'],
  );
  final path = result?.files.single.path;
  if (path == null || !context.mounted) return;

  _showLoadingDialog(context, 'Importando inventario...');
  try {
    final bytes = await File(path).readAsBytes();
    final archive = ZipDecoder().decodeBytes(bytes);

    final manifestEntry = _findEntry(archive, _manifestFileName);
    if (manifestEntry == null) {
      throw Exception('El archivo no tiene un $_manifestFileName (¿es un respaldo de Ventas Cell?)');
    }
    final manifest = jsonDecode(utf8.decode(manifestEntry.content as List<int>)) as Map<String, dynamic>;

    final db = DatabaseHelper.instance;
    final existingCategories = await db.getCategories();
    final categoryIdByName = {
      for (final c in existingCategories) c.name.trim().toLowerCase(): c.id!,
    };

    for (final rawName in (manifest['categories'] as List? ?? [])) {
      final name = rawName.toString().trim();
      final key = name.toLowerCase();
      if (name.isEmpty || categoryIdByName.containsKey(key)) continue;
      final id = await db.insertCategory(Category(name: name));
      categoryIdByName[key] = id;
    }

    final existingProducts = await db.getProducts();
    final docsDir = await getApplicationDocumentsDirectory();

    var created = 0;
    var updated = 0;
    var photosRestored = 0;

    for (final raw in (manifest['products'] as List? ?? [])) {
      final map = raw as Map<String, dynamic>;
      final name = (map['name'] as String? ?? '').trim();
      if (name.isEmpty) continue;
      final barcodes = (map['barcodes'] as List? ?? []).map((b) => b.toString()).toList();

      final categoryName = map['categoryName'] as String?;
      final categoryId = categoryName != null ? categoryIdByName[categoryName.trim().toLowerCase()] : null;

      // Busca un producto ya existente para actualizar en vez de duplicar:
      // primero por código de barras; si no tiene (a granel), por nombre.
      Product? match;
      if (barcodes.isNotEmpty) {
        for (final existing in existingProducts) {
          if (barcodes.any(existing.matchesBarcode)) {
            match = existing;
            break;
          }
        }
      }
      if (match == null) {
        for (final existing in existingProducts) {
          if (existing.name.trim().toLowerCase() == name.toLowerCase()) {
            match = existing;
            break;
          }
        }
      }

      String? photoPath = match?.photoPath;
      final photoFile = map['photoFile'] as String?;
      if (photoFile != null) {
        final entry = _findEntry(archive, photoFile);
        if (entry != null && entry.isFile) {
          final photoBytes = entry.content as List<int>;
          final destName = 'product_${DateTime.now().microsecondsSinceEpoch}_${p.basename(photoFile)}';
          final destPath = p.join(docsDir.path, destName);
          await File(destPath).writeAsBytes(photoBytes);
          photoPath = destPath;
          photosRestored++;
        }
      }

      final product = Product(
        id: match?.id,
        name: name,
        description: map['description'] as String?,
        barcodes: barcodes,
        categoryId: categoryId,
        purchasePrice: (map['purchasePrice'] as num?)?.toDouble() ?? 0,
        salePrice: (map['salePrice'] as num?)?.toDouble() ?? 0,
        currentStock: (map['currentStock'] as num?)?.toInt() ?? 0,
        minStock: (map['minStock'] as num?)?.toInt() ?? 0,
        photoPath: photoPath,
        soldByWeight: map['soldByWeight'] as bool? ?? false,
      );

      if (match != null) {
        await db.updateProduct(product);
        updated++;
      } else {
        await db.insertProduct(product);
        created++;
      }
    }

    if (!context.mounted) return;
    Navigator.of(context, rootNavigator: true).pop();
    _showResultDialog(
      context,
      'Importación completa',
      '$created producto(s) nuevo(s), $updated actualizado(s), $photosRestored foto(s) restaurada(s).',
    );
  } catch (e) {
    if (!context.mounted) return;
    Navigator.of(context, rootNavigator: true).pop();
    _showResultDialog(
      context,
      'No se pudo importar',
      'Revisa que el archivo sea un respaldo válido de Ventas Cell.\n\n$e',
    );
  }
}

void _showLoadingDialog(BuildContext context, String message) {
  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (_) => AlertDialog(
      content: Row(
        children: [
          const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.5)),
          const SizedBox(width: 16),
          Expanded(child: Text(message)),
        ],
      ),
    ),
  );
}

void _showResultDialog(BuildContext context, String title, String message) {
  showDialog(
    context: context,
    builder: (_) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('OK'))],
    ),
  );
}
