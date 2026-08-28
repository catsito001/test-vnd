// lib/utils/printing.dart
//
// Parte 8 — Impresión térmica (ticket ESC/POS, Bluetooth 58mm/80mm).
//
// Genera el ticket con `esc_pos_utils` (clase Generator) respetando el
// tamaño de papel configurado en Ajustes (58mm ≈ 32 columnas / 80mm ≈ 48
// columnas) y lo envía por Bluetooth clásico (SPP) con
// `print_bluetooth_thermal` a la impresora emparejada guardada en
// `AppSettings.printerMacAddress`.
//
// Nota: el prompt original pedía `esc_pos_bluetooth` (o `blue_thermal_printer`
// como alternativa) para el transporte Bluetooth, pero ambos paquetes están
// abandonados desde 2021 (dependen de `jcenter()`, que ya no existe, y del
// embedding viejo de Android) y no compilan con las versiones actuales de
// Flutter/Android Gradle Plugin. `print_bluetooth_thermal` cubre lo mismo
// (Bluetooth clásico/SPP, solo Android) y sí se mantiene activo. La
// generación del ticket en sí (`esc_pos_utils`, más abajo) no cambia.
//
// `printReceipt` nunca lanza excepciones ni bloquea el flujo de la venta:
// la venta ya quedó guardada en SQLite antes de llamarla, así que
// cualquier problema (impresora apagada, fuera de rango, sin emparejar,
// permisos denegados) se devuelve dentro de un [PrintReceiptResult] para
// que la pantalla muestre el aviso correspondiente y, si quiere, ofrezca
// "Reintentar impresión". Esta misma función se reutilizará desde el
// Detalle de Venta (Parte 9) para "Reimprimir Ticket".

import 'package:esc_pos_utils/esc_pos_utils.dart';
import 'package:intl/intl.dart';
import 'package:print_bluetooth_thermal/print_bluetooth_thermal.dart';

import '../data/database.dart';
import '../models/models.dart';
import 'permissions.dart';
import 'utils.dart';

// ===========================================================================
// Resultado de un intento de impresión
// ===========================================================================

enum PrintOutcome {
  success,
  noPrinterConfigured,
  permissionDenied,
  printerNotFound,
  printError,
}

class PrintReceiptResult {
  final PrintOutcome outcome;
  final String message;
  const PrintReceiptResult(this.outcome, this.message);

  bool get isSuccess => outcome == PrintOutcome.success;
}

// ===========================================================================
// Punto de entrada público
// ===========================================================================

Future<PrintReceiptResult> printReceipt(Sale sale, List<SaleItem> items) async {
  final settings = await DatabaseHelper.instance.getSettings();
  final address = settings.printerMacAddress?.trim();

  if (address == null || address.isEmpty) {
    return const PrintReceiptResult(
      PrintOutcome.noPrinterConfigured,
      'No hay una impresora configurada. Ve a Ajustes > Impresora Bluetooth.',
    );
  }

  // Sin `BuildContext` disponible en este punto del flujo (se imprime
  // justo después de confirmar la venta), así que se piden los permisos
  // directamente sin diálogo de justificación previo (Parte 12).
  final hasPermissions = await ensureBluetoothPermissions(null, showRationale: false);
  if (!hasPermissions) {
    return const PrintReceiptResult(
      PrintOutcome.permissionDenied,
      'Se necesitan permisos de Bluetooth para poder imprimir.',
    );
  }

  // Bluetooth clásico (SPP) no se "descubre": la impresora ya tiene que
  // estar emparejada desde Ajustes de Android; acá solo nos conectamos
  // directo por su MAC guardada en Ajustes (Parte 10).
  final connected = await PrintBluetoothThermal.connect(macPrinterAddress: address);
  if (!connected) {
    return PrintReceiptResult(
      PrintOutcome.printerNotFound,
      'No se pudo conectar con "${settings.printerName ?? address}". Verifica que esté '
      'encendida, emparejada y a rango.',
    );
  }

  try {
    final bytes = await _buildTicketBytes(settings, sale, items);
    final printed = await PrintBluetoothThermal.writeBytes(bytes);
    if (printed) {
      return const PrintReceiptResult(PrintOutcome.success, 'Ticket impreso correctamente.');
    }
    return const PrintReceiptResult(PrintOutcome.printError, 'La impresora no confirmó la impresión.');
  } catch (e) {
    return PrintReceiptResult(PrintOutcome.printError, 'Error al imprimir: $e');
  } finally {
    await PrintBluetoothThermal.disconnect;
  }
}

// ===========================================================================
// Construcción del ticket (ESC/POS)
// ===========================================================================

final DateFormat _ticketDateFormat = DateFormat('dd/MM/yyyy HH:mm');

Future<List<int>> _buildTicketBytes(
  AppSettings settings,
  Sale sale,
  List<SaleItem> items,
) async {
  final is58mm = settings.printerSize != '80mm';
  final paperSize = is58mm ? PaperSize.mm58 : PaperSize.mm80;
  final profile = await CapabilityProfile.load();
  final generator = Generator(paperSize, profile);

  // 58mm ≈ 32 columnas de texto, 80mm ≈ 48 (Parte 8 del prompt). Se usa
  // para truncar el nombre del producto a lo que entra en su columna
  // dentro de la fila Producto/Total (que reparte 8/12 al nombre).
  final totalColumns = is58mm ? 32 : 48;
  final nameMaxChars = ((totalColumns * 8) ~/ 12) - 1;

  String? sellerName;
  if (sale.sellerId != null) {
    final sellers = await DatabaseHelper.instance.getSellers();
    final match = sellers.where((s) => s.id == sale.sellerId);
    if (match.isNotEmpty) sellerName = match.first.name;
  }

  List<int> bytes = [];

  // Encabezado del negocio (opcional).
  if (settings.businessName.trim().isNotEmpty) {
    bytes += generator.text(
      settings.businessName,
      styles: const PosStyles(align: PosAlign.center, bold: true),
    );
    if (settings.businessAddress.trim().isNotEmpty) {
      bytes += generator.text(
        settings.businessAddress,
        styles: const PosStyles(align: PosAlign.center),
      );
    }
    if (settings.businessPhone.trim().isNotEmpty) {
      bytes += generator.text(
        settings.businessPhone,
        styles: const PosStyles(align: PosAlign.center),
      );
    }
    bytes += generator.hr();
  }

  // Datos de la venta.
  bytes += generator.text('Venta #${sale.id}', styles: const PosStyles(bold: true));
  bytes += generator.text(_ticketDateFormat.format(sale.date));
  if (sellerName != null && sellerName.isNotEmpty) {
    bytes += generator.text('Atendido por: $sellerName');
  }
  bytes += generator.hr();

  // Encabezado de la tabla de productos.
  bytes += generator.row([
    PosColumn(text: 'Producto', width: 8, styles: const PosStyles(bold: true)),
    PosColumn(text: 'Total', width: 4, styles: const PosStyles(bold: true, align: PosAlign.right)),
  ]);

  for (final item in items) {
    bytes += generator.row([
      PosColumn(text: _truncate(item.productName, nameMaxChars), width: 8),
      PosColumn(
        text: formatCurrency(item.subtotal),
        width: 4,
        styles: const PosStyles(align: PosAlign.right),
      ),
    ]);
    // Segunda línea pequeña con cantidad y precio unitario.
    bytes += generator.text('  ${item.quantity} x ${formatCurrency(item.unitPrice)}');
  }

  bytes += generator.hr();

  // TOTAL en negrita/tamaño doble.
  bytes += generator.row([
    PosColumn(
      text: 'TOTAL',
      width: 6,
      styles: const PosStyles(bold: true, height: PosTextSize.size2),
    ),
    PosColumn(
      text: formatCurrency(sale.total),
      width: 6,
      styles: const PosStyles(bold: true, align: PosAlign.right, height: PosTextSize.size2),
    ),
  ]);

  bytes += generator.feed(1);

  // Método de pago como pie de página.
  bytes += generator.text(
    sale.paymentMethod.label,
    styles: const PosStyles(align: PosAlign.center, bold: true),
  );
  if (sale.paymentMethod == PaymentMethod.efectivo && sale.amountReceived != null) {
    bytes += generator.text(
      'Recibido: ${formatCurrency(sale.amountReceived!)}',
      styles: const PosStyles(align: PosAlign.center),
    );
    bytes += generator.text(
      'Vuelto: ${formatCurrency(sale.change ?? 0)}',
      styles: const PosStyles(align: PosAlign.center),
    );
  }

  // Mensaje de agradecimiento configurable.
  if (settings.receiptFooterMessage.trim().isNotEmpty) {
    bytes += generator.feed(1);
    bytes += generator.text(
      settings.receiptFooterMessage,
      styles: const PosStyles(align: PosAlign.center),
    );
  }

  // Corte de papel.
  bytes += generator.feed(2);
  bytes += generator.cut();

  return bytes;
}

String _truncate(String text, int maxChars) {
  if (maxChars <= 0 || text.length <= maxChars) return text;
  return '${text.substring(0, maxChars - 1)}.';
}
