// lib/screens/catalog_screen.dart
//
// Parte 6 — Catálogo de Productos: vista grid accesible desde el icono de
// grilla en la pantalla principal (Parte 2), para agregar productos al
// carrito sin necesidad de escanear (código dañado, producto a granel,
// etc). Comparte el mismo CartProvider que ScannerHomeScreen.
//
// Se muestra como overlay sobre la cámara: la pantalla se navega con una
// ruta translúcida (ver `openProductCatalog` en home_screen.dart) para que
// el preview de la cámara siga visible detrás del fondo oscurecido.

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/database.dart';
import '../models/models.dart';
import '../providers/cart_provider.dart';
import '../theme.dart';
import '../utils/utils.dart';
import 'product_screens.dart';

class ProductCatalogScreen extends StatefulWidget {
  const ProductCatalogScreen({super.key});

  @override
  State<ProductCatalogScreen> createState() => _ProductCatalogScreenState();
}

class _ProductCatalogScreenState extends State<ProductCatalogScreen> {
  final _db = DatabaseHelper.instance;
  final _searchController = TextEditingController();

  List<Category> _categories = [];
  int? _selectedCategoryId; // null = "Todas"
  List<Product> _products = [];
  bool _loading = true;

  // Banner verde "agregado", igual que en la pantalla principal.
  Product? _addedProduct;
  Timer? _bannerTimer;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _bannerTimer?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final categories = await _db.getCategories();
    final products = await _db.getProducts(
      query: _searchController.text,
      categoryId: _selectedCategoryId,
    );
    if (!mounted) return;
    setState(() {
      _categories = categories;
      _products = products;
      _loading = false;
    });
  }

  // --- Agregar al carrito -------------------------------------------------

  void _addToCart(Product product) {
    context.read<CartProvider>().addProduct(product);
    _bannerTimer?.cancel();
    setState(() => _addedProduct = product);
    _bannerTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) setState(() => _addedProduct = null);
    });
  }

  // --- FAB "+": mismo flujo de la Parte 5 (escanear -> Nuevo Producto) ---

  Future<void> _openNewProductFlow() async {
    final code = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => const BarcodeScannerScreen(title: 'Código del nuevo producto'),
      ),
    );
    if (!mounted) return;
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => NewProductScreen(initialBarcode: code)),
    );
    if (saved == true) _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Container(
        color: AppColors.overlay,
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildTopBar(),
              const SizedBox(height: 4),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: TextField(
                  controller: _searchController,
                  style: const TextStyle(color: Colors.black87),
                  decoration: const InputDecoration(
                    hintText: 'Buscar producto...',
                    prefixIcon: Icon(Icons.search),
                    filled: true,
                    fillColor: Colors.white,
                  ),
                  onChanged: (_) => _load(),
                ),
              ),
              const SizedBox(height: 10),
              _buildCategoryChips(),
              const SizedBox(height: 6),
              Expanded(
                child: _loading
                    ? const Center(child: CircularProgressIndicator(color: Colors.white))
                    : _products.isEmpty
                        ? _buildEmptyState()
                        : _buildGrid(),
              ),
              if (_addedProduct != null) _buildAddedBanner(_addedProduct!),
            ],
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _openNewProductFlow,
        child: const Icon(Icons.add),
      ),
    );
  }

  // --- Barra superior -------------------------------------------------

  Widget _buildTopBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 4, 16, 0),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.close, color: Colors.white),
            onPressed: () => Navigator.of(context).pop(),
          ),
          const Expanded(
            child: Text(
              'Catálogo de Productos',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ),
          const SizedBox(width: 40), // balancea el icono de cerrar
        ],
      ),
    );
  }

  // --- Chips de categoría -------------------------------------------------

  Widget _buildCategoryChips() {
    return SizedBox(
      height: 40,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        children: [
          _CategoryChip(
            label: 'Todas',
            selected: _selectedCategoryId == null,
            onTap: () {
              setState(() => _selectedCategoryId = null);
              _load();
            },
          ),
          for (final c in _categories)
            _CategoryChip(
              label: c.name,
              selected: _selectedCategoryId == c.id,
              onTap: () {
                setState(() => _selectedCategoryId = c.id);
                _load();
              },
            ),
        ],
      ),
    );
  }

  // --- Grid de productos -------------------------------------------------

  Widget _buildGrid() {
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
      itemCount: _products.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        childAspectRatio: 0.78,
      ),
      itemBuilder: (context, i) {
        final product = _products[i];
        return _ProductCard(product: product, onTap: () => _addToCart(product));
      },
    );
  }

  Widget _buildEmptyState() {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.inventory_2_outlined, size: 48, color: Colors.white54),
          SizedBox(height: 12),
          Text('No hay productos', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          SizedBox(height: 4),
          Text(
            'Toca + para agregar uno nuevo.',
            style: TextStyle(color: Colors.white70, fontSize: 12),
          ),
        ],
      ),
    );
  }

  // --- Banner verde "agregado" (igual que al escanear) -------------------

  Widget _buildAddedBanner(Product product) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.success,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          const Icon(Icons.check_circle, color: Colors.white),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '${product.name} agregado  ${formatCurrency(product.salePrice)}',
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

class _CategoryChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _CategoryChip({required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        label: Text(label),
        selected: selected,
        onSelected: (_) => onTap(),
        backgroundColor: Colors.white70,
        selectedColor: AppColors.primary,
        labelStyle: TextStyle(
          color: selected ? Colors.white : Colors.black87,
          fontWeight: selected ? FontWeight.bold : FontWeight.normal,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide.none,
        ),
      ),
    );
  }
}

class _ProductCard extends StatelessWidget {
  final Product product;
  final VoidCallback onTap;
  const _ProductCard({required this.product, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    color: const Color(0xFFEFEFEF),
                    child: product.photoPath != null
                        ? Image.file(File(product.photoPath!), fit: BoxFit.cover)
                        : const Center(
                            child: Icon(Icons.inventory_2_outlined, size: 36, color: Colors.black26),
                          ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                product.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
              ),
              const SizedBox(height: 4),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    formatCurrency(product.salePrice),
                    style: const TextStyle(
                      color: AppColors.success,
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                  Text(
                    'Cant: ${product.currentStock}',
                    style: const TextStyle(color: Colors.black45, fontSize: 11),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
