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
  int quantity;

  CartItem({required this.product, this.quantity = 1});

  double get subtotal => product.salePrice * quantity;
  double get costSubtotal => product.purchasePrice * quantity;
}

class CartProvider extends ChangeNotifier {
  final List<CartItem> _items = [];

  List<CartItem> get items => List.unmodifiable(_items);

  bool get isEmpty => _items.isEmpty;

  /// Suma de unidades (lo que se muestra como "X items" en la pantalla
  /// principal), no la cantidad de líneas distintas.
  int get totalQuantity => _items.fold(0, (sum, item) => sum + item.quantity);

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

  void clear() {
    _items.clear();
    notifyListeners();
  }
}
