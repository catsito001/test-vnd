// lib/screens/sales_history_screen.dart
//
// Parte 9 — Historial de Ventas.
//
// `SalesHistoryScreen`: tabs "Hoy" | "Semana" | "Mes" | "Todo" filtran las
// ventas por rango de fecha; la tarjeta resumen (Ventas / Ingresos /
// Ganancia) y el listado se recalculan según la tab activa.
//
// `SaleDetailScreen`: detalle de una venta puntual, con "Reimprimir Ticket"
// (reutiliza `printReceipt` de la Parte 8) y "Eliminar Venta" (con
// confirmación; no repone stock, tal como pide el prompt).

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../data/database.dart';
import '../models/models.dart';
import '../theme.dart';
import '../utils/printing.dart';
import '../utils/sales_export.dart';
import '../utils/utils.dart';

final DateFormat _dateFormat = DateFormat('dd/MM/yyyy HH:mm');

IconData _paymentIcon(PaymentMethod method) {
  switch (method) {
    case PaymentMethod.efectivo:
      return Icons.payments_outlined;
    case PaymentMethod.yape:
      return Icons.qr_code_2;
    case PaymentMethod.plin:
      return Icons.smartphone;
    case PaymentMethod.tarjeta:
      return Icons.credit_card;
  }
}

// ===========================================================================
// SalesHistoryScreen
// ===========================================================================

enum _RangeTab { hoy, semana, mes, todo }

class SalesHistoryScreen extends StatefulWidget {
  const SalesHistoryScreen({super.key});

  @override
  State<SalesHistoryScreen> createState() => _SalesHistoryScreenState();
}

class _SalesHistoryScreenState extends State<SalesHistoryScreen>
    with SingleTickerProviderStateMixin {
  final _db = DatabaseHelper.instance;
  late final TabController _tabController;

  bool _loading = true;
  List<Sale> _sales = [];
  Map<String, int> _itemCounts = {};

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _RangeTab.values.length, vsync: this);
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) _load();
    });
    _load();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  _RangeTab get _selectedTab => _RangeTab.values[_tabController.index];

  (DateTime?, DateTime?) _rangeFor(_RangeTab tab) {
    final now = DateTime.now();
    final startOfToday = DateTime(now.year, now.month, now.day);
    switch (tab) {
      case _RangeTab.hoy:
        return (startOfToday, now);
      case _RangeTab.semana:
        // Últimos 7 días (hoy incluido).
        return (startOfToday.subtract(const Duration(days: 6)), now);
      case _RangeTab.mes:
        return (DateTime(now.year, now.month, 1), now);
      case _RangeTab.todo:
        return (null, null);
    }
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final (from, to) = _rangeFor(_selectedTab);
    final sales = await _db.getSales(from: from, to: to);
    final counts = await _db.getSaleItemCounts(sales.map((s) => s.id).toList());
    if (!mounted) return;
    setState(() {
      _sales = sales;
      _itemCounts = counts;
      _loading = false;
    });
  }

  Future<void> _openDetail(Sale sale) async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => SaleDetailScreen(saleId: sale.id)),
    );
    // SaleDetailScreen devuelve `true` cuando la venta fue eliminada.
    if (changed == true) _load();
  }

  void _exportExcel() {
    const labels = {
      _RangeTab.hoy: 'hoy',
      _RangeTab.semana: 'semana',
      _RangeTab.mes: 'mes',
      _RangeTab.todo: 'todo',
    };
    exportSalesExcel(context, sales: _sales, rangeLabel: labels[_selectedTab]!);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Historial de Ventas'),
        actions: [
          IconButton(
            icon: const Icon(Icons.file_download_outlined),
            tooltip: 'Exportar a Excel',
            onPressed: _exportExcel,
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          labelColor: AppColors.primary,
          unselectedLabelColor: Colors.black54,
          indicatorColor: AppColors.primary,
          tabs: const [
            Tab(text: 'Hoy'),
            Tab(text: 'Semana'),
            Tab(text: 'Mes'),
            Tab(text: 'Todo'),
          ],
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                    child: _SummaryCard(sales: _sales),
                  ),
                  Expanded(
                    child: _sales.isEmpty ? _buildEmptyState() : _buildList(),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildList() {
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
      itemCount: _sales.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, i) {
        final sale = _sales[i];
        return _SaleRow(
          sale: sale,
          itemCount: _itemCounts[sale.id] ?? 0,
          onTap: () => _openDetail(sale),
        );
      },
    );
  }

  Widget _buildEmptyState() {
    // Envuelto en ListView (en vez de Center) para que RefreshIndicator
    // siga pudiendo activarse con el gesto de deslizar hacia abajo.
    return ListView(
      children: const [
        SizedBox(height: 90),
        Icon(Icons.receipt_long_outlined, size: 48, color: Colors.black26),
        SizedBox(height: 12),
        Center(
          child: Text(
            'No hay ventas en este período',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
        ),
      ],
    );
  }
}

class _SummaryCard extends StatelessWidget {
  final List<Sale> sales;
  const _SummaryCard({required this.sales});

  @override
  Widget build(BuildContext context) {
    final count = sales.length;
    final income = sales.fold(0.0, (sum, s) => sum + s.total);
    final profit = sales.fold(0.0, (sum, s) => sum + s.profit);

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 8),
      decoration: BoxDecoration(
        color: AppColors.primary,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Expanded(child: _SummaryColumn(value: '$count', label: 'Ventas')),
          Container(width: 1, height: 40, color: Colors.white24),
          Expanded(child: _SummaryColumn(value: formatCurrency(income), label: 'Ingresos')),
          Container(width: 1, height: 40, color: Colors.white24),
          Expanded(child: _SummaryColumn(value: formatCurrency(profit), label: 'Ganancia')),
        ],
      ),
    );
  }
}

class _SummaryColumn extends StatelessWidget {
  final String value;
  final String label;
  const _SummaryColumn({required this.value, required this.label});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          value,
          textAlign: TextAlign.center,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
        ),
        const SizedBox(height: 4),
        Text(label, style: const TextStyle(color: Colors.white70, fontSize: 12)),
      ],
    );
  }
}

class _SaleRow extends StatelessWidget {
  final Sale sale;
  final int itemCount;
  final VoidCallback onTap;
  const _SaleRow({required this.sale, required this.itemCount, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('#${sale.id}', style: const TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    Text(
                      '$itemCount prod. • ${_dateFormat.format(sale.date)}',
                      style: const TextStyle(color: Colors.black54, fontSize: 12),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(_paymentIcon(sale.paymentMethod), size: 14, color: Colors.black45),
                        const SizedBox(width: 4),
                        Text(
                          sale.paymentMethod.label,
                          style: const TextStyle(color: Colors.black45, fontSize: 12),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              Text(
                formatCurrency(sale.total),
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ===========================================================================
// SaleDetailScreen
// ===========================================================================

class SaleDetailScreen extends StatefulWidget {
  final String saleId;
  const SaleDetailScreen({super.key, required this.saleId});

  @override
  State<SaleDetailScreen> createState() => _SaleDetailScreenState();
}

class _SaleDetailScreenState extends State<SaleDetailScreen> {
  final _db = DatabaseHelper.instance;

  bool _loading = true;
  Sale? _sale;
  List<SaleItem> _items = [];
  String? _sellerName;
  bool _printing = false;
  bool _deleting = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final sale = await _db.getSaleById(widget.saleId);
    final items = await _db.getSaleItems(widget.saleId);

    String? sellerName;
    if (sale?.sellerId != null) {
      final sellers = await _db.getSellers();
      final match = sellers.where((s) => s.id == sale!.sellerId);
      if (match.isNotEmpty) sellerName = match.first.name;
    }

    if (!mounted) return;
    setState(() {
      _sale = sale;
      _items = items;
      _sellerName = sellerName;
      _loading = false;
    });
  }

  // --- Reimprimir Ticket (reutiliza printReceipt de la Parte 8) ----------

  Future<void> _reprint() async {
    final sale = _sale;
    if (sale == null || _printing) return;
    setState(() => _printing = true);
    final result = await printReceipt(sale, _items);
    if (!mounted) return;
    setState(() => _printing = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(result.message),
        backgroundColor: result.isSuccess ? AppColors.success : AppColors.warning,
      ),
    );
  }

  // --- Eliminar Venta -------------------------------------------------

  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Eliminar venta'),
        content: Text(
          '¿Seguro que quieres eliminar la venta #${widget.saleId}? '
          'El stock no se repone automáticamente y esta acción no se puede deshacer.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: TextButton.styleFrom(foregroundColor: AppColors.danger),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (confirmed != true || _deleting) return;

    setState(() => _deleting = true);
    await _db.deleteSale(widget.saleId);
    if (!mounted) return;
    // Avisa a SalesHistoryScreen que debe recargar su listado.
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Detalle de Venta')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _sale == null
              ? const Center(child: Text('Esta venta ya no existe.'))
              : _buildBody(_sale!),
    );
  }

  Widget _buildBody(Sale sale) {
    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
            children: [
              Text('#${sale.id}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 20)),
              const SizedBox(height: 4),
              Text(_dateFormat.format(sale.date), style: const TextStyle(color: Colors.black54)),
              if (_sellerName != null) ...[
                const SizedBox(height: 2),
                Text(
                  'Atendido por: $_sellerName',
                  style: const TextStyle(color: Colors.black54, fontSize: 13),
                ),
              ],
              const SizedBox(height: 10),
              Row(
                children: [
                  Icon(_paymentIcon(sale.paymentMethod), size: 16, color: AppColors.primary),
                  const SizedBox(width: 6),
                  Text(sale.paymentMethod.label, style: const TextStyle(fontWeight: FontWeight.w600)),
                ],
              ),
              const Divider(height: 32),
              for (final item in _items) _DetailLine(item: item),
              const Divider(height: 32),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('TOTAL', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20)),
                  Text(
                    formatCurrency(sale.total),
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 20),
                  ),
                ],
              ),
              if (sale.paymentMethod == PaymentMethod.efectivo && sale.amountReceived != null) ...[
                const SizedBox(height: 14),
                _InfoRow(label: 'Recibido', value: formatCurrency(sale.amountReceived!)),
                const SizedBox(height: 4),
                _InfoRow(label: 'Vuelto', value: formatCurrency(sale.change ?? 0)),
              ],
            ],
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ElevatedButton.icon(
                  onPressed: _printing ? null : _reprint,
                  icon: _printing
                      ? const SizedBox(
                          height: 16,
                          width: 16,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.print),
                  label: const Text('Reimprimir Ticket'),
                ),
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  onPressed: _deleting ? null : _delete,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.danger,
                    side: const BorderSide(color: AppColors.danger),
                    minimumSize: const Size.fromHeight(50),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  icon: _deleting
                      ? const SizedBox(
                          height: 16,
                          width: 16,
                          child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.danger),
                        )
                      : const Icon(Icons.delete_outline),
                  label: const Text('Eliminar Venta'),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _DetailLine extends StatelessWidget {
  final SaleItem item;
  const _DetailLine({required this.item});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item.productName, style: const TextStyle(fontWeight: FontWeight.w600)),
                Text(
                  item.soldByWeight
                      ? '${formatWeight(item.quantity)} x ${formatCurrency(item.unitPrice)}/kg'
                      : '${item.quantity} x ${formatCurrency(item.unitPrice)}',
                  style: const TextStyle(color: Colors.black54, fontSize: 12),
                ),
              ],
            ),
          ),
          Text(formatCurrency(item.subtotal), style: const TextStyle(fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  const _InfoRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: const TextStyle(color: Colors.black54)),
        Text(value, style: const TextStyle(fontWeight: FontWeight.w600)),
      ],
    );
  }
}
