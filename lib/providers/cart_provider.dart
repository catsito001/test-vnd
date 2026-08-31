// lib/providers/cart_provider.dart
//
// Estado del carrito de la venta actual. Es un ChangeNotifier (paquete
// `provider`) para que ScannerHomeScreen (Parte 2), ProductCatalogScreen
// (Parte 6) y ReviewOrderScreen (Parte 7) compartan exactamente el mismo
// carrito, como pide el prompt.

import 'package:flutter/foundation.dart';

import '../models/models.dart';

class CartItem {
  final Product product;
  /// Unidades para productos normales; GRAMOS para productos con
  /// `soldByWeight == true` (ver comentario en `Product.soldByWeight`).
  int quantity;

  CartItem({required this.product, this.quantity = 1});

  double get subtotal =>
      product.soldByWeight ? product.salePrice * (quantity / 1000) : product.salePrice * quantity;

  double get costSubtotal =>
      product.soldByWeight ? product.purchasePrice * (quantity / 1000) : product.purchasePrice * quantity;
}

class CartProvider extends ChangeNotifier {
  final List<CartItem> _items = [];

  List<CartItem> get items => List.unmodifiable(_items);

  bool get isEmpty => _items.isEmpty;

  /// Suma de unidades (lo que se muestra como "X items" en la pantalla
  /// principal), no la cantidad de líneas distintas. Los productos por
  /// peso cuentan como 1 artículo (sumar sus gramos daría un número sin
  /// sentido, ej. "253 items" por 0.25 kg de plátano).
  int get totalQuantity =>
      _items.fold(0, (sum, item) => sum + (item.product.soldByWeight ? 1 : item.quantity));

  double get total => _items.fold(0, (sum, item) => sum + item.subtotal);

  double get totalCost => _items.fold(0, (sum, item) => sum + item.costSubtotal);

  int _indexOf(int productId) => _items.indexWhere((i) => i.product.id == productId);

  /// Agrega 1 unidad del producto; si ya estaba en el carrito, incrementa
  /// su cantidad en vez de duplicar la línea.
  void addProduct(Product product) {
    final index = _indexOf(product.id!);
    if (index >= 0) {
      _items[index].quantity++;
    } else {
      _items.add(CartItem(product: product));
    }
    notifyListeners();
  }

  void incrementQuantity(int productId) {
    final index = _indexOf(productId);
    if (index >= 0) {
      _items[index].quantity++;
      notifyListeners();
    }
  }

  /// Si la cantidad llega a 0, la línea se elimina del carrito.
  void decrementQuantity(int productId) {
    final index = _indexOf(productId);
    if (index < 0) return;
    if (_items[index].quantity <= 1) {
      _items.removeAt(index);
    } else {
      _items[index].quantity--;
    }
    notifyListeners();
  }

  void removeItem(int productId) {
    _items.removeWhere((i) => i.product.id == productId);
    notifyListeners();
  }

  /// Agrega `grams` de un producto por peso; si ya estaba en el carrito,
  /// SUMA a lo que ya tenía (igual que `addProduct` con unidades) en vez
  /// de reemplazarlo.
  void addWeightedProduct(Product product, int grams) {
    if (grams <= 0) return;
    final index = _indexOf(product.id!);
    if (index >= 0) {
      _items[index].quantity += grams;
    } else {
      _items.add(CartItem(product: product, quantity: grams));
    }
    notifyListeners();
  }

  /// Fija (no suma) el peso de una línea ya agregada, para cuando se edita
  /// la cantidad de un producto por peso que ya está en el carrito. Con
  /// `grams <= 0` la línea se elimina.
  void setWeight(int productId, int grams) {
    final index = _indexOf(productId);
    if (index < 0) return;
    if (grams <= 0) {
      _items.removeAt(index);
    } else {
      _items[index].quantity = grams;
    }
    notifyListeners();
  }

  /// Refresca los datos (nombre, precio, foto, etc.) de un producto que ya
  /// está en el carrito, por ejemplo después de editarlo desde ahí mismo.
  /// Conserva la cantidad actual. Si el producto no está en el carrito, no
  /// hace nada.
  void updateProductData(Product updated) {
    final index = _indexOf(updated.id!);
    if (index < 0) return;
    _items[index] = CartItem(product: updated, quantity: _items[index].quantity);
    notifyListeners();
  }

  void clear() {
    _items.clear();
    notifyListeners();
  }
}
