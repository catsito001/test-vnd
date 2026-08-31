// lib/utils/sales_export.dart
//
// Exporta el Historial de Ventas (el rango de fechas activo en pantalla:
// Hoy/Semana/Mes/Todo) a un .xlsx, para llevar la contabilidad o
// declararlo después. Dos hojas: "Ventas" (una fila por venta, con
// totales al final) y "Detalle" (una fila por línea/producto vendido).

import 'dart:io';

import 'package:cross_file/cross_file.dart';
import 'package:excel/excel.dart' as xls;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../data/database.dart';
import '../models/models.dart';
import 'utils.dart';

final DateFormat _dateTimeFormat = DateFormat('dd/MM/yyyy HH:mm');

/// [rangeLabel] es solo para el nombre del archivo (ej. "hoy", "mes"), sin
/// espacios ni tildes.
Future<void> exportSalesExcel(
  BuildContext context, {
  required List<Sale> sales,
  required String rangeLabel,
}) async {
  if (sales.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('No hay ventas en este rango para exportar.')),
    );
    return;
  }

  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (_) => const AlertDialog(
      content: Row(
        children: [
          SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.5)),
          SizedBox(width: 16),
          Expanded(child: Text('Generando Excel...')),
        ],
      ),
    ),
  );

  try {
    final db = DatabaseHelper.instance;
    final sellers = await db.getSellers();
    final sellerNameById = {for (final s in sellers) s.id: s.name};

    final excel = xls.Excel.createExcel();
    final salesSheet = excel['Ventas'];
    final detailSheet = excel['Detalle'];

    salesSheet.appendRow([
      xls.TextCellValue('Fecha'),
      xls.TextCellValue('N° Venta'),
      xls.TextCellValue('Vendedor'),
      xls.TextCellValue('Método de Pago'),
      xls.TextCellValue('Costo'),
      xls.TextCellValue('Total'),
      xls.TextCellValue('Ganancia'),
    ]);
    detailSheet.appendRow([
      xls.TextCellValue('Fecha'),
      xls.TextCellValue('N° Venta'),
      xls.TextCellValue('Producto'),
      xls.TextCellValue('Cantidad'),
      xls.TextCellValue('Precio Unit.'),
      xls.TextCellValue('Subtotal'),
    ]);

    var total = 0.0;
    var totalCost = 0.0;

    for (final sale in sales) {
      final dateText = _dateTimeFormat.format(sale.date);
      final sellerName = sale.sellerId != null ? (sellerNameById[sale.sellerId] ?? '-') : '-';

      salesSheet.appendRow([
        xls.TextCellValue(dateText),
        xls.TextCellValue(sale.id),
        xls.TextCellValue(sellerName),
        xls.TextCellValue(sale.paymentMethod.label),
        xls.DoubleCellValue(sale.totalCost),
        xls.DoubleCellValue(sale.total),
        xls.DoubleCellValue(sale.profit),
      ]);
      total += sale.total;
      totalCost += sale.totalCost;

      final items = await db.getSaleItems(sale.id);
      for (final item in items) {
        detailSheet.appendRow([
          xls.TextCellValue(dateText),
          xls.TextCellValue(sale.id),
          xls.TextCellValue(item.productName),
          xls.TextCellValue(item.soldByWeight ? formatWeight(item.quantity) : '${item.quantity}'),
          xls.DoubleCellValue(item.unitPrice),
          xls.DoubleCellValue(item.subtotal),
        ]);
      }
    }

    salesSheet.appendRow([
      xls.TextCellValue(''),
      xls.TextCellValue(''),
      xls.TextCellValue(''),
      xls.TextCellValue('TOTAL'),
      xls.DoubleCellValue(totalCost),
      xls.DoubleCellValue(total),
      xls.DoubleCellValue(total - totalCost),
    ]);

    // `Excel.createExcel()` arranca con una hoja "Sheet1" vacía de más.
    try {
      excel.delete('Sheet1');
    } catch (_) {
      // No existía (o ya se usó ese nombre): no afecta el resultado.
    }

    final fileBytes = excel.save();
    if (fileBytes == null) throw Exception('No se pudo generar el Excel');

    final tempDir = await getTemporaryDirectory();
    final stamp = DateTime.now().millisecondsSinceEpoch;
    final path = p.join(tempDir.path, 'ventas_cell_ventas_${rangeLabel}_$stamp.xlsx');
    await File(path).writeAsBytes(fileBytes);

    if (!context.mounted) return;
    Navigator.of(context, rootNavigator: true).pop(); // cierra "Generando..."

    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(path)],
        text: 'Historial de ventas de Ventas Cell (${sales.length} ventas)',
      ),
    );
  } catch (e) {
    if (!context.mounted) return;
    Navigator.of(context, rootNavigator: true).pop();
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('No se pudo exportar'),
        content: Text('Ocurrió un error generando el Excel.\n\n$e'),
        actions: [TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('OK'))],
      ),
    );
  }
}
