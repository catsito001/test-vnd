// lib/data/database.dart
//
// DatabaseHelper: singleton que maneja toda la base de datos SQLite
// (sqflite) de la app: categorías, productos, vendedores, ventas,
// líneas de venta y configuración (Parte 1 del prompt).

import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../models/models.dart';

class DatabaseHelper {
  DatabaseHelper._internal();
  static final DatabaseHelper instance = DatabaseHelper._internal();

  static Database? _db;
  static const _uuid = Uuid();

  Future<Database> get database async {
    _db ??= await _initDb();
    return _db!;
  }

  Future<Database> _initDb() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, 'vende_movil.db');
    return openDatabase(
      path,
      version: 2,
      onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  /// v1 -> v2: agrega `activeSellerId` a `app_settings` (vendedor activo,
  /// usado como "Atendido por" por defecto en Parte 7/8).
  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await db.execute('ALTER TABLE app_settings ADD COLUMN activeSellerId INTEGER');
    }
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE categories (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE products (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        description TEXT,
        barcodes TEXT NOT NULL,
        categoryId INTEGER,
        purchasePrice REAL NOT NULL DEFAULT 0,
        salePrice REAL NOT NULL DEFAULT 0,
        currentStock INTEGER NOT NULL DEFAULT 0,
        minStock INTEGER NOT NULL DEFAULT 0,
        photoPath TEXT,
        FOREIGN KEY (categoryId) REFERENCES categories (id) ON DELETE SET NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE sellers (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE sales (
        id TEXT PRIMARY KEY,
        date TEXT NOT NULL,
        total REAL NOT NULL,
        totalCost REAL NOT NULL,
        paymentMethod TEXT NOT NULL,
        amountReceived REAL,
        change REAL,
        sellerId INTEGER,
        FOREIGN KEY (sellerId) REFERENCES sellers (id) ON DELETE SET NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE sale_items (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        saleId TEXT NOT NULL,
        productId INTEGER NOT NULL,
        productName TEXT NOT NULL,
        unitPrice REAL NOT NULL,
        unitCost REAL NOT NULL,
        quantity INTEGER NOT NULL,
        subtotal REAL NOT NULL,
        FOREIGN KEY (saleId) REFERENCES sales (id) ON DELETE CASCADE,
        FOREIGN KEY (productId) REFERENCES products (id)
      )
    ''');

    await db.execute('''
      CREATE TABLE app_settings (
        id INTEGER PRIMARY KEY CHECK (id = 1),
        businessName TEXT,
        businessAddress TEXT,
        businessPhone TEXT,
        yapeQrImagePath TEXT,
        printerSize TEXT DEFAULT '58mm',
        printerMacAddress TEXT,
        printerName TEXT,
        receiptFooterMessage TEXT DEFAULT '¡Gracias por su compra!',
        activeSellerId INTEGER,
        FOREIGN KEY (activeSellerId) REFERENCES sellers (id) ON DELETE SET NULL
      )
    ''');

    // Fila única de configuración, y un par de categorías de ejemplo para
    // no arrancar con el inventario completamente vacío.
    await db.insert('app_settings', AppSettings().toMap());
    for (final name in ['Alimentos', 'Bebidas', 'Cuidado Personal', 'Limpieza']) {
      await db.insert('categories', {'name': name});
    }
  }

  // ---------------------------------------------------------------------
  // CATEGORÍAS
  // ---------------------------------------------------------------------

  Future<int> insertCategory(Category category) async {
    final db = await database;
    return db.insert('categories', category.toMap());
  }

  Future<List<Category>> getCategories() async {
    final db = await database;
    final rows = await db.query('categories', orderBy: 'name ASC');
    return rows.map(Category.fromMap).toList();
  }

  Future<int> updateCategory(Category category) async {
    final db = await database;
    return db.update('categories', category.toMap(),
        where: 'id = ?', whereArgs: [category.id]);
  }

  /// Devuelve false (y no borra nada) si la categoría todavía tiene
  /// productos asociados.
  Future<bool> deleteCategory(int id) async {
    final db = await database;
    final count = Sqflite.firstIntValue(await db.rawQuery(
          'SELECT COUNT(*) FROM products WHERE categoryId = ?',
          [id],
        )) ??
        0;
    if (count > 0) return false;
    await db.delete('categories', where: 'id = ?', whereArgs: [id]);
    return true;
  }

  // ---------------------------------------------------------------------
  // PRODUCTOS
  // ---------------------------------------------------------------------

  Future<int> insertProduct(Product product) async {
    final db = await database;
    return db.insert('products', product.toMap());
  }

  Future<int> updateProduct(Product product) async {
    final db = await database;
    return db.update('products', product.toMap(),
        where: 'id = ?', whereArgs: [product.id]);
  }

  Future<int> deleteProduct(int id) async {
    final db = await database;
    return db.delete('products', where: 'id = ?', whereArgs: [id]);
  }

  /// Lista de productos, con filtro opcional por texto (nombre o código de
  /// barra) y/o por categoría. Se usa en Inventario y en el Catálogo.
  Future<List<Product>> getProducts({String? query, int? categoryId}) async {
    final db = await database;
    final where = <String>[];
    final args = <Object?>[];

    if (categoryId != null) {
      where.add('categoryId = ?');
      args.add(categoryId);
    }
    if (query != null && query.trim().isNotEmpty) {
      where.add('(name LIKE ? OR barcodes LIKE ?)');
      args.add('%${query.trim()}%');
      args.add('%${query.trim()}%');
    }

    final rows = await db.query(
      'products',
      where: where.isEmpty ? null : where.join(' AND '),
      whereArgs: args.isEmpty ? null : args,
      orderBy: 'name ASC',
    );
    return rows.map(Product.fromMap).toList();
  }

  Future<Product?> getProductById(int id) async {
    final db = await database;
    final rows = await db.query('products', where: 'id = ?', whereArgs: [id]);
    if (rows.isEmpty) return null;
    return Product.fromMap(rows.first);
  }

  /// Busca el producto cuyo campo `barcodes` contiene exactamente `code`.
  /// Se hace en memoria porque `barcodes` guarda varios códigos separados
  /// por coma en una sola columna.
  Future<Product?> getProductByBarcode(String code) async {
    final all = await getProducts();
    for (final p in all) {
      if (p.matchesBarcode(code)) return p;
    }
    return null;
  }

  /// Agrega `newBarcode` a la lista de códigos de un producto ya existente
  /// (usado por "Vincular a producto existente").
  Future<void> addBarcodeToProduct(int productId, String newBarcode) async {
    final product = await getProductById(productId);
    if (product == null) return;
    if (product.matchesBarcode(newBarcode)) return; // ya lo tiene
    final updated = product.copyWith(
      barcodes: [...product.barcodes, newBarcode.trim()],
    );
    await updateProduct(updated);
  }

  // ---------------------------------------------------------------------
  // VENDEDORES
  // ---------------------------------------------------------------------

  Future<int> insertSeller(Seller seller) async {
    final db = await database;
    return db.insert('sellers', seller.toMap());
  }

  Future<List<Seller>> getSellers() async {
    final db = await database;
    final rows = await db.query('sellers', orderBy: 'name ASC');
    return rows.map(Seller.fromMap).toList();
  }

  Future<int> deleteSeller(int id) async {
    final db = await database;
    return db.delete('sellers', where: 'id = ?', whereArgs: [id]);
  }

  // ---------------------------------------------------------------------
  // VENTAS
  // ---------------------------------------------------------------------

  /// Genera un id corto de venta, ej. "F5E4BC11".
  String generateSaleId() =>
      _uuid.v4().replaceAll('-', '').substring(0, 8).toUpperCase();

  /// Inserta la venta y todas sus líneas dentro de una transacción, y
  /// descuenta el stock de cada producto vendido. Si algo falla, no se
  /// guarda nada.
  Future<void> insertSaleWithItems(Sale sale, List<SaleItem> items) async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.insert('sales', sale.toMap());
      for (final item in items) {
        await txn.insert('sale_items', item.toMap());
        await _decreaseStock(txn, item.productId, item.quantity);
      }
    });
  }

  Future<void> _decreaseStock(Transaction txn, int productId, int qty) async {
    await txn.rawUpdate(
      'UPDATE products SET currentStock = currentStock - ? WHERE id = ?',
      [qty, productId],
    );
  }

  /// Ventas dentro de un rango de fechas (usado por las tabs Hoy/Semana/
  /// Mes/Todo del Historial). Si `from`/`to` son null, trae todas.
  Future<List<Sale>> getSales({DateTime? from, DateTime? to}) async {
    final db = await database;
    final where = <String>[];
    final args = <Object?>[];

    if (from != null) {
      where.add('date >= ?');
      args.add(from.toIso8601String());
    }
    if (to != null) {
      where.add('date <= ?');
      args.add(to.toIso8601String());
    }

    final rows = await db.query(
      'sales',
      where: where.isEmpty ? null : where.join(' AND '),
      whereArgs: args.isEmpty ? null : args,
      orderBy: 'date DESC',
    );
    return rows.map(Sale.fromMap).toList();
  }

  Future<Sale?> getSaleById(String id) async {
    final db = await database;
    final rows = await db.query('sales', where: 'id = ?', whereArgs: [id]);
    if (rows.isEmpty) return null;
    return Sale.fromMap(rows.first);
  }

  Future<List<SaleItem>> getSaleItems(String saleId) async {
    final db = await database;
    final rows =
        await db.query('sale_items', where: 'saleId = ?', whereArgs: [saleId]);
    return rows.map(SaleItem.fromMap).toList();
  }

  /// Cantidad de líneas de producto distintas por venta (ej. {"F5E4BC11": 3}),
  /// usado por el listado del Historial de Ventas (Parte 9) para mostrar
  /// "X prod." sin tener que cargar todas las líneas completas de cada venta.
  Future<Map<String, int>> getSaleItemCounts(List<String> saleIds) async {
    if (saleIds.isEmpty) return {};
    final db = await database;
    final placeholders = List.filled(saleIds.length, '?').join(',');
    final rows = await db.rawQuery(
      'SELECT saleId, COUNT(*) as cnt FROM sale_items WHERE saleId IN ($placeholders) GROUP BY saleId',
      saleIds,
    );
    return {for (final row in rows) row['saleId'] as String: row['cnt'] as int};
  }

  /// Borra una venta y sus líneas. No repone el stock automáticamente
  /// (comportamiento indicado en la Parte 9 del prompt).
  Future<void> deleteSale(String saleId) async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.delete('sale_items', where: 'saleId = ?', whereArgs: [saleId]);
      await txn.delete('sales', where: 'id = ?', whereArgs: [saleId]);
    });
  }

  // ---------------------------------------------------------------------
  // CONFIGURACIÓN (AppSettings)
  // ---------------------------------------------------------------------

  Future<AppSettings> getSettings() async {
    final db = await database;
    final rows = await db.query('app_settings', where: 'id = 1');
    if (rows.isEmpty) return AppSettings();
    return AppSettings.fromMap(rows.first);
  }

  Future<void> saveSettings(AppSettings settings) async {
    final db = await database;
    final count = Sqflite.firstIntValue(
          await db.rawQuery('SELECT COUNT(*) FROM app_settings WHERE id = 1'),
        ) ??
        0;
    if (count == 0) {
      await db.insert('app_settings', settings.toMap());
    } else {
      await db.update('app_settings', settings.toMap(),
          where: 'id = 1');
    }
  }
}
