// lib/utils/weight_entry_sheet.dart
//
// Bottom sheet para elegir la cantidad (en kg o g) de un producto que se
// vende por peso (`Product.soldByWeight`), con el subtotal calculado en
// vivo (`Product.salePrice`/`purchasePrice` son precio por KILO en estos
// productos). Devuelve los gramos elegidos, o `null` si se cancela.
//
// Lo usan:
// - ProductCatalogScreen, al tocar un producto por peso en el catálogo
//   (estos productos suelen no tener código de barras para escanear).
// - ScannerHomeScreen, tanto si se escanea un código que resulta ser de
//   un producto por peso, como para editar el peso de una línea que ya
//   está en el carrito (con `initialGrams`).

import 'package:flutter/material.dart';

import '../models/models.dart';
import '../theme.dart';
import 'utils.dart';

enum _WeightUnit { kg, g }

Future<int?> showWeightEntrySheet(
  BuildContext context, {
  required Product product,
  int? initialGrams,
}) {
  return showModalBottomSheet<int>(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (context) => _WeightEntrySheet(product: product, initialGrams: initialGrams),
  );
}

/// "19.700" -> "19.7", "1.000" -> "1", "0.750" -> "0.75". Sin la unidad.
String _trimmedKg(double kg) {
  var text = kg.toStringAsFixed(3);
  text = text.replaceFirst(RegExp(r'0+$'), '');
  text = text.replaceFirst(RegExp(r'\.$'), '');
  return text;
}

class _WeightEntrySheet extends StatefulWidget {
  final Product product;
  final int? initialGrams;
  const _WeightEntrySheet({required this.product, this.initialGrams});

  @override
  State<_WeightEntrySheet> createState() => _WeightEntrySheetState();
}

class _WeightEntrySheetState extends State<_WeightEntrySheet> {
  late _WeightUnit _unit;
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    final grams = widget.initialGrams ?? 0;
    // Si ya venía un valor y es un múltiplo exacto de 1000, arranca en kg
    // (más natural para pesos grandes); si no, en gramos.
    _unit = (grams > 0 && grams % 1000 == 0) ? _WeightUnit.kg : _WeightUnit.g;
    _controller = TextEditingController(text: grams == 0 ? '' : _textFor(grams, _unit));
    _controller.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  String _textFor(int grams, _WeightUnit unit) =>
      unit == _WeightUnit.kg ? _trimmedKg(grams / 1000) : grams.toString();

  int get _grams {
    final value = double.tryParse(_controller.text.replaceAll(',', '.')) ?? 0;
    final grams = _unit == _WeightUnit.kg ? value * 1000 : value;
    if (grams.isNaN || grams < 0) return 0;
    return grams.round();
  }

  double get _kg => _grams / 1000;

  double get _subtotal => widget.product.salePrice * _kg;

  void _setUnit(_WeightUnit unit) {
    if (unit == _unit) return;
    final currentGrams = _grams;
    setState(() {
      _unit = unit;
      _controller.text = currentGrams == 0 ? '' : _textFor(currentGrams, unit);
    });
  }

  void _applyPreset(int grams) {
    setState(() => _controller.text = _textFor(grams, _unit));
  }

  @override
  Widget build(BuildContext context) {
    final product = widget.product;
    final isEditing = widget.initialGrams != null;
    final presets = _unit == _WeightUnit.g ? const [50, 100, 250, 500] : const [1000, 2000, 5000, 10000];

    return Padding(
      // Empuja el sheet arriba del teclado.
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(color: Colors.black12, borderRadius: BorderRadius.circular(2)),
                ),
              ),
              Text(
                product.name,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 4),
              Text(
                '${formatCurrency(product.salePrice)}/kg · Stock ${formatWeight(product.currentStock)}',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.black54),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: _UnitButton(label: 'kg', selected: _unit == _WeightUnit.kg, onTap: () => _setUnit(_WeightUnit.kg)),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _UnitButton(label: 'g', selected: _unit == _WeightUnit.g, onTap: () => _setUnit(_WeightUnit.g)),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _controller,
                autofocus: true,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                  labelText: 'Cantidad (${_unit == _WeightUnit.kg ? 'kg' : 'g'})',
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final g in presets)
                    ActionChip(
                      label: Text(_unit == _WeightUnit.g ? '$g g' : '${_trimmedKg(g / 1000)} kg'),
                      onPressed: () => _applyPreset(g),
                    ),
                ],
              ),
              const SizedBox(height: 20),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 14),
                decoration: BoxDecoration(color: const Color(0xFFF5F6F7), borderRadius: BorderRadius.circular(12)),
                child: Text(
                  '${_trimmedKg(_kg)} kg × ${formatCurrency(product.salePrice)}/kg = ${formatCurrency(_subtotal)}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: _grams > 0 ? () => Navigator.of(context).pop(_grams) : null,
                child: Text(isEditing ? 'Actualizar' : 'Agregar'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _UnitButton extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _UnitButton({required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(24),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: selected ? AppColors.primary : Colors.white,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: selected ? AppColors.primary : Colors.black26),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (selected) ...[
              const Icon(Icons.check, size: 18, color: Colors.white),
              const SizedBox(width: 6),
            ],
            Text(
              label,
              style: TextStyle(
                color: selected ? Colors.white : Colors.black87,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
