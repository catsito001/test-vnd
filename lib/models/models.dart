// lib/models/models.dart
//
// Todos los modelos de datos de la app en un solo archivo (Parte 1 del prompt).
// Cada modelo sabe convertirse a/desde un Map<String, dynamic> para poder
// guardarse y leerse de SQLite a través de DatabaseHelper (lib/database.dart).

/// Métodos de pago soportados. Ninguno procesa el cobro real dentro de la
/// app: solo quedan registrados junto a la venta.
enum PaymentMethod { efectivo, yape, plin, tarjeta }

extension PaymentMethodX on PaymentMethod {
  String get value => name;

  static PaymentMethod fromValue(String value) {
    return PaymentMethod.values.firstWhere(
      (e) => e.name == value,
      orElse: () => PaymentMethod.efectivo,
    );
  }

  String get label {
    switch (this) {
      case PaymentMethod.efectivo:
        return 'Efectivo';
      case PaymentMethod.yape:
        return 'Yape';
      case PaymentMethod.plin:
        return 'Plin';
      case PaymentMethod.tarjeta:
        return 'Tarjeta';
    }
  }
}

/// Categoría de producto (Alimentos, Bebidas, Cuidado Personal, etc.)
class Category {
  final int? id;
  final String name;

  Category({this.id, required this.name});

  Map<String, dynamic> toMap() => {
        if (id != null) 'id': id,
        'name': name,
      };

  factory Category.fromMap(Map<String, dynamic> map) => Category(
        id: map['id'] as int?,
        name: map['name'] as String,
      );

  Category copyWith({int? id, String? name}) =>
      Category(id: id ?? this.id, name: name ?? this.name);
}

/// Producto del inventario. Puede responder a varios códigos de barra
/// (se guardan en SQLite como un solo string separado por comas).
class Product {
  final int? id;
  final String name;
  final String? description;
  final List<String> barcodes;
  final int? categoryId;
  final double purchasePrice; // Precio Compra
  final double salePrice; // Precio Venta
  final int currentStock; // Stock Actual
  final int minStock; // Stock Mínimo
  final String? photoPath;

  /// Si es `true`, el producto se vende por peso: `purchasePrice`/
  /// `salePrice` son precio por KILO, y `currentStock`/`minStock` quedan
  /// en GRAMOS en vez de unidades (así no hace falta cambiar el tipo de
  /// esas columnas en SQLite). Pensado para productos a granel que
  /// normalmente no tienen código de barras (fruta, verdura, etc.).
  final bool soldByWeight;

  Product({
    this.id,
    required this.name,
    this.description,
    required this.barcodes,
    this.categoryId,
    required this.purchasePrice,
    required this.salePrice,
    this.currentStock = 0,
    this.minStock = 0,
    this.photoPath,
    this.soldByWeight = false,
  });

  bool get isLowStock => currentStock <= minStock;

  /// true si `code` coincide con alguno de los códigos de barra del producto.
  bool matchesBarcode(String code) =>
      barcodes.map((b) => b.trim()).contains(code.trim());

  Map<String, dynamic> toMap() => {
        if (id != null) 'id': id,
        'name': name,
        'description': description,
        'barcodes': barcodes.map((b) => b.trim()).join(','),
        'categoryId': categoryId,
        'purchasePrice': purchasePrice,
        'salePrice': salePrice,
        'currentStock': currentStock,
        'minStock': minStock,
        'photoPath': photoPath,
        'soldByWeight': soldByWeight ? 1 : 0,
      };

  factory Product.fromMap(Map<String, dynamic> map) => Product(
        id: map['id'] as int?,
        name: map['name'] as String,
        description: map['description'] as String?,
        barcodes: ((map['barcodes'] as String?) ?? '')
            .split(',')
            .map((b) => b.trim())
            .where((b) => b.isNotEmpty)
            .toList(),
        categoryId: map['categoryId'] as int?,
        purchasePrice: (map['purchasePrice'] as num).toDouble(),
        salePrice: (map['salePrice'] as num).toDouble(),
        currentStock: map['currentStock'] as int,
        minStock: map['minStock'] as int,
        photoPath: map['photoPath'] as String?,
        soldByWeight: (map['soldByWeight'] as int?) == 1,
      );

  Product copyWith({
    int? id,
    String? name,
    String? description,
    List<String>? barcodes,
    int? categoryId,
    double? purchasePrice,
    double? salePrice,
    int? currentStock,
    int? minStock,
    String? photoPath,
    bool? soldByWeight,
  }) =>
      Product(
        id: id ?? this.id,
        name: name ?? this.name,
        description: description ?? this.description,
        barcodes: barcodes ?? this.barcodes,
        categoryId: categoryId ?? this.categoryId,
        purchasePrice: purchasePrice ?? this.purchasePrice,
        salePrice: salePrice ?? this.salePrice,
        currentStock: currentStock ?? this.currentStock,
        minStock: minStock ?? this.minStock,
        photoPath: photoPath ?? this.photoPath,
        soldByWeight: soldByWeight ?? this.soldByWeight,
      );
}

/// Vendedor. Se usa para el "Atendido por" del ticket impreso.
class Seller {
  final int? id;
  final String name;

  Seller({this.id, required this.name});

  Map<String, dynamic> toMap() => {
        if (id != null) 'id': id,
        'name': name,
      };

  factory Seller.fromMap(Map<String, dynamic> map) => Seller(
        id: map['id'] as int?,
        name: map['name'] as String,
      );
}

/// Cabecera de una venta.
class Sale {
  final String id; // ej. "F5E4BC11"
  final DateTime date;
  final double total;
  final double totalCost; // suma de purchasePrice*qty, para calcular ganancia
  final PaymentMethod paymentMethod;
  final double? amountReceived; // solo si paymentMethod == efectivo
  final double? change; // Vuelto
  final int? sellerId;

  Sale({
    required this.id,
    required this.date,
    required this.total,
    required this.totalCost,
    required this.paymentMethod,
    this.amountReceived,
    this.change,
    this.sellerId,
  });

  double get profit => total - totalCost;

  Map<String, dynamic> toMap() => {
        'id': id,
        'date': date.toIso8601String(),
        'total': total,
        'totalCost': totalCost,
        'paymentMethod': paymentMethod.value,
        'amountReceived': amountReceived,
        'change': change,
        'sellerId': sellerId,
      };

  factory Sale.fromMap(Map<String, dynamic> map) => Sale(
        id: map['id'] as String,
        date: DateTime.parse(map['date'] as String),
        total: (map['total'] as num).toDouble(),
        totalCost: (map['totalCost'] as num).toDouble(),
        paymentMethod: PaymentMethodX.fromValue(map['paymentMethod'] as String),
        amountReceived: (map['amountReceived'] as num?)?.toDouble(),
        change: (map['change'] as num?)?.toDouble(),
        sellerId: map['sellerId'] as int?,
      );
}

/// Línea de una venta. Guarda una copia del nombre/precio del producto al
/// momento de la venta, por si el producto se edita o elimina después.
class SaleItem {
  final int? id;
  final String saleId;
  final int productId;
  final String productName;
  final double unitPrice;
  final double unitCost;
  final int quantity;
  final double subtotal;

  /// Copia de `Product.soldByWeight` al momento de la venta: si es
  /// `true`, `quantity` está en gramos (no en unidades) y `unitPrice`/
  /// `unitCost` son precio por kilo. Se guarda acá para que el ticket y
  /// el Historial de Ventas se sigan viendo bien aunque el producto se
  /// edite o borre después.
  final bool soldByWeight;

  SaleItem({
    this.id,
    required this.saleId,
    required this.productId,
    required this.productName,
    required this.unitPrice,
    required this.unitCost,
    required this.quantity,
    required this.subtotal,
    this.soldByWeight = false,
  });

  Map<String, dynamic> toMap() => {
        if (id != null) 'id': id,
        'saleId': saleId,
        'productId': productId,
        'productName': productName,
        'unitPrice': unitPrice,
        'unitCost': unitCost,
        'quantity': quantity,
        'subtotal': subtotal,
        'soldByWeight': soldByWeight ? 1 : 0,
      };

  factory SaleItem.fromMap(Map<String, dynamic> map) => SaleItem(
        id: map['id'] as int?,
        saleId: map['saleId'] as String,
        productId: map['productId'] as int,
        productName: map['productName'] as String,
        unitPrice: (map['unitPrice'] as num).toDouble(),
        unitCost: (map['unitCost'] as num).toDouble(),
        quantity: map['quantity'] as int,
        subtotal: (map['subtotal'] as num).toDouble(),
        soldByWeight: (map['soldByWeight'] as int?) == 1,
      );
}

/// Configuración general del negocio. Se guarda como una sola fila (id = 1)
/// en la tabla `app_settings`.
class AppSettings {
  final String businessName;
  final String businessAddress;
  final String businessPhone;
  final String? yapeQrImagePath;
  final String printerSize; // "58mm" | "80mm"
  final String? printerMacAddress;
  final String? printerName;
  final String receiptFooterMessage;

  /// Vendedor que queda seleccionado como "activo" en Ajustes > Vendedores.
  /// Se usa como `sellerId` por defecto al confirmar una venta (Parte 7) y
  /// como "Atendido por" en el ticket impreso (Parte 8), sin tener que
  /// elegirlo en cada venta.
  final int? activeSellerId;

  AppSettings({
    this.businessName = '',
    this.businessAddress = '',
    this.businessPhone = '',
    this.yapeQrImagePath,
    this.printerSize = '58mm',
    this.printerMacAddress,
    this.printerName,
    this.receiptFooterMessage = '¡Gracias por su compra!',
    this.activeSellerId,
  });

  Map<String, dynamic> toMap() => {
        'id': 1,
        'businessName': businessName,
        'businessAddress': businessAddress,
        'businessPhone': businessPhone,
        'yapeQrImagePath': yapeQrImagePath,
        'printerSize': printerSize,
        'printerMacAddress': printerMacAddress,
        'printerName': printerName,
        'receiptFooterMessage': receiptFooterMessage,
        'activeSellerId': activeSellerId,
      };

  factory AppSettings.fromMap(Map<String, dynamic> map) => AppSettings(
        businessName: map['businessName'] as String? ?? '',
        businessAddress: map['businessAddress'] as String? ?? '',
        businessPhone: map['businessPhone'] as String? ?? '',
        yapeQrImagePath: map['yapeQrImagePath'] as String?,
        printerSize: map['printerSize'] as String? ?? '58mm',
        printerMacAddress: map['printerMacAddress'] as String?,
        printerName: map['printerName'] as String?,
        receiptFooterMessage: map['receiptFooterMessage'] as String? ??
            '¡Gracias por su compra!',
        activeSellerId: map['activeSellerId'] as int?,
      );

  AppSettings copyWith({
    String? businessName,
    String? businessAddress,
    String? businessPhone,
    String? yapeQrImagePath,
    String? printerSize,
    String? printerMacAddress,
    String? printerName,
    String? receiptFooterMessage,
    int? activeSellerId,
  }) =>
      AppSettings(
        businessName: businessName ?? this.businessName,
        businessAddress: businessAddress ?? this.businessAddress,
        businessPhone: businessPhone ?? this.businessPhone,
        yapeQrImagePath: yapeQrImagePath ?? this.yapeQrImagePath,
        printerSize: printerSize ?? this.printerSize,
        printerMacAddress: printerMacAddress ?? this.printerMacAddress,
        printerName: printerName ?? this.printerName,
        receiptFooterMessage: receiptFooterMessage ?? this.receiptFooterMessage,
        activeSellerId: activeSellerId ?? this.activeSellerId,
      );
}
