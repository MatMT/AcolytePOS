import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

void main() => runApp(const AcolytePosApp());

const _geminiKey = String.fromEnvironment('GEMINI_API_KEY');

class Product {
  const Product(this.id, this.name, this.price, this.aliases);
  final String id;
  final String name;
  final double price;
  final List<String> aliases;
}

const catalog = <Product>[
  Product('cafe', 'Café', 0.50, ['cafe', 'café', 'cafes', 'cafés']),
  Product('pan', 'Pan', 0.40, ['pan', 'semita', 'semitas', 'pan dulce', 'panes']),
  Product('soda', 'Soda', 0.75, ['soda', 'sodas', 'gaseosa', 'gaseosas', 'refresco']),
  Product('agua', 'Agua', 0.50, ['agua', 'aguas']),
  Product('churro', 'Churro', 0.35, ['churro', 'churros', 'snack', 'snacks']),
];

class CartLine {
  CartLine(this.product, this.qty);
  final Product product;
  int qty;
  double get lineTotal => product.price * qty;
}

class ParsedOrder {
  ParsedOrder({
    required this.items,
    required this.total,
    required this.pagoCon,
    required this.vuelto,
    required this.resumen,
    this.fromAi = false,
  });
  final List<CartLine> items;
  final double total;
  final double pagoCon;
  final double vuelto;
  final String resumen;
  final bool fromAi;
}

class AcolytePosApp extends StatelessWidget {
  const AcolytePosApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AcolytePOS',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF1B5E20),
          brightness: Brightness.light,
        ),
        useMaterial3: true,
      ),
      home: const PosScreen(),
    );
  }
}

class PosScreen extends StatefulWidget {
  const PosScreen({super.key});

  @override
  State<PosScreen> createState() => _PosScreenState();
}

class _PosScreenState extends State<PosScreen> {
  final _nlController = TextEditingController();
  final _pagoController = TextEditingController();
  final Map<String, CartLine> _cart = {};
  bool _loading = false;
  String? _status;

  double get _total => _cart.values.fold(0.0, (s, l) => s + l.lineTotal);

  double get _pago =>
      double.tryParse(_pagoController.text.replaceAll(',', '.')) ?? 0;

  double get _vuelto {
    final v = _pago - _total;
    return v < 0 ? 0 : v;
  }

  void _addProduct(Product p, [int qty = 1]) {
    setState(() {
      final existing = _cart[p.id];
      if (existing == null) {
        _cart[p.id] = CartLine(p, qty);
      } else {
        existing.qty += qty;
      }
      _status = null;
    });
  }

  void _bump(Product p, int delta) {
    setState(() {
      final line = _cart[p.id];
      if (line == null) return;
      line.qty += delta;
      if (line.qty <= 0) _cart.remove(p.id);
    });
  }

  void _clearSale() {
    setState(() {
      _cart.clear();
      _nlController.clear();
      _pagoController.clear();
      _status = 'Nueva venta lista';
    });
  }

  void _confirmSale() {
    if (_cart.isEmpty) {
      setState(() => _status = 'Agrega productos primero');
      return;
    }
    if (_pago < _total) {
      setState(() => _status = 'Pago insuficiente');
      return;
    }
    final msg =
        'Venta OK · Total \$${_total.toStringAsFixed(2)} · Vuelto \$${_vuelto.toStringAsFixed(2)}';
    _clearSale();
    setState(() => _status = msg);
  }

  Future<void> _parseNl() async {
    final text = _nlController.text.trim();
    if (text.isEmpty) {
      setState(() => _status = 'Escribe el pedido');
      return;
    }
    setState(() {
      _loading = true;
      _status = 'Procesando…';
    });
    try {
      ParsedOrder? parsed;
      if (_geminiKey.isNotEmpty) {
        parsed = await _parseWithGemini(text);
      }
      parsed ??= parseLocalOrder(text);
      setState(() {
        _cart
          ..clear()
          ..addEntries(parsed!.items.map((l) => MapEntry(l.product.id, l)));
        if (parsed.pagoCon > 0) {
          _pagoController.text = parsed.pagoCon.toStringAsFixed(2);
        }
        _status = parsed.fromAi ? 'IA: ${parsed.resumen}' : 'Local: ${parsed.resumen}';
      });
    } catch (_) {
      final local = parseLocalOrder(text);
      setState(() {
        _cart
          ..clear()
          ..addEntries(local.items.map((l) => MapEntry(l.product.id, l)));
        if (local.pagoCon > 0) {
          _pagoController.text = local.pagoCon.toStringAsFixed(2);
        }
        _status = 'Fallback local: ${local.resumen}';
      });
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<ParsedOrder?> _parseWithGemini(String userText) async {
    final uri = Uri.parse(
      'https://generativelanguage.googleapis.com/v1beta/models/gemini-1.5-flash:generateContent?key=$_geminiKey',
    );
    const system = '''
Eres el cajero de una tiendita parroquial. Analiza el pedido y responde UNICAMENTE JSON valido (sin markdown).
Precios: Cafe 0.50, Pan/Semita 0.40, Soda/Gaseosa 0.75, Agua 0.50, Churro 0.35.
Esquema:
{"resumen":"...","items":[{"nombre":"Cafe","cant":1,"precio":0.50}],"total":0.0,"pago_con":0.0,"vuelto":0.0}
''';
    final body = {
      'contents': [
        {
          'parts': [
            {'text': '$system\n\nPedido: $userText'},
          ],
        }
      ],
      'generationConfig': {'temperature': 0.1},
    };
    final res = await http
        .post(uri,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(body))
        .timeout(const Duration(seconds: 12));
    if (res.statusCode != 200) throw Exception('Gemini ${res.statusCode}');
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    final raw =
        data['candidates']?[0]?['content']?['parts']?[0]?['text'] as String?;
    if (raw == null) throw Exception('Empty Gemini');
    return parsedOrderFromJson(raw, fromAi: true);
  }

  @override
  void dispose() {
    _nlController.dispose();
    _pagoController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final lines = _cart.values.toList();
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7F5),
      appBar: AppBar(
        title: const Text('AcolytePOS'),
        backgroundColor: const Color(0xFF1B5E20),
        foregroundColor: Colors.white,
        actions: [
          TextButton(
            onPressed: _clearSale,
            child: const Text('Nueva venta', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth >= 720;
            final products = _ProductGrid(onTap: (p) => _addProduct(p));
            final panel = _OrderPanel(
              lines: lines,
              total: _total,
              vuelto: _vuelto,
              pagoController: _pagoController,
              nlController: _nlController,
              loading: _loading,
              status: _status,
              onBump: _bump,
              onParse: _parseNl,
              onConfirm: _confirmSale,
              onPagoChanged: () => setState(() {}),
            );
            if (wide) {
              return Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(flex: 5, child: products),
                  Expanded(flex: 6, child: panel),
                ],
              );
            }
            return ListView(
              padding: EdgeInsets.zero,
              children: [
                SizedBox(height: 240, child: products),
                SizedBox(
                  height: constraints.maxHeight > 240
                      ? constraints.maxHeight - 240
                      : 520,
                  child: panel,
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _ProductGrid extends StatelessWidget {
  const _ProductGrid({required this.onTap});
  final void Function(Product) onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: GridView.count(
        crossAxisCount: 2,
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        childAspectRatio: 1.55,
        children: [
          for (final p in catalog)
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: const Color(0xFF1B5E20),
                side: const BorderSide(color: Color(0xFF1B5E20), width: 2),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16)),
              ),
              onPressed: () => onTap(p),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(p.name,
                      style: const TextStyle(
                          fontSize: 20, fontWeight: FontWeight.w700)),
                  Text('\$${p.price.toStringAsFixed(2)}',
                      style: const TextStyle(fontSize: 16)),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _OrderPanel extends StatelessWidget {
  const _OrderPanel({
    required this.lines,
    required this.total,
    required this.vuelto,
    required this.pagoController,
    required this.nlController,
    required this.loading,
    required this.status,
    required this.onBump,
    required this.onParse,
    required this.onConfirm,
    required this.onPagoChanged,
  });

  final List<CartLine> lines;
  final double total;
  final double vuelto;
  final TextEditingController pagoController;
  final TextEditingController nlController;
  final bool loading;
  final String? status;
  final void Function(Product, int) onBump;
  final VoidCallback onParse;
  final VoidCallback onConfirm;
  final VoidCallback onPagoChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('Pedido rapido (lenguaje natural)',
              style: TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: nlController,
                  minLines: 1,
                  maxLines: 2,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => onParse(),
                  decoration: const InputDecoration(
                    hintText: 'Ej: 2 semitas y un cafe, me pagaron con uno de 5',
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: loading ? null : onParse,
                child: loading
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : const Text('IA'),
              ),
            ],
          ),
          if (status != null) ...[
            const SizedBox(height: 8),
            Text(status!, style: TextStyle(color: Colors.grey.shade700)),
          ],
          const SizedBox(height: 12),
          const Text('Carrito', style: TextStyle(fontWeight: FontWeight.w600)),
          Expanded(
            child: lines.isEmpty
                ? const Center(child: Text('Toca un producto o escribe el pedido'))
                : ListView.builder(
                    itemCount: lines.length,
                    itemBuilder: (_, i) {
                      final l = lines[i];
                      return ListTile(
                        dense: true,
                        title: Text('${l.product.name} x ${l.qty}'),
                        subtitle: Text('\$${l.product.price.toStringAsFixed(2)} c/u'),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              onPressed: () => onBump(l.product, -1),
                              icon: const Icon(Icons.remove_circle_outline),
                            ),
                            Text('\$${l.lineTotal.toStringAsFixed(2)}',
                                style: const TextStyle(fontWeight: FontWeight.w700)),
                            IconButton(
                              onPressed: () => onBump(l.product, 1),
                              icon: const Icon(Icons.add_circle_outline),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
          TextField(
            controller: pagoController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))
            ],
            onChanged: (_) => onPagoChanged(),
            decoration: const InputDecoration(
              labelText: 'Pago con',
              prefixText: '\$ ',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFFE8F5E9),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              children: [
                Text(
                  'TOTAL  \$${total.toStringAsFixed(2)}',
                  style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 6),
                Text(
                  'VUELTO  \$${vuelto.toStringAsFixed(2)}',
                  style: const TextStyle(
                    fontSize: 42,
                    fontWeight: FontWeight.w900,
                    color: Color(0xFF1B5E20),
                    height: 1.05,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          FilledButton(
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(52),
              backgroundColor: const Color(0xFF1B5E20),
            ),
            onPressed: onConfirm,
            child: const Text('Cobrar / Confirmar', style: TextStyle(fontSize: 18)),
          ),
        ],
      ),
    );
  }
}

ParsedOrder parseLocalOrder(String raw) {
  final text = raw.toLowerCase();
  final items = <CartLine>[];
  for (final p in catalog) {
    final cleaned = _qtyForProduct(text, p);
    if (cleaned > 0) items.add(CartLine(p, cleaned));
  }
  final pago = _extractPago(text);
  final total = items.fold(0.0, (s, l) => s + l.lineTotal);
  final vuelto =
      pago > 0 ? (pago - total).clamp(0, double.infinity).toDouble() : 0.0;
  final resumen = items.isEmpty
      ? 'No reconoci productos'
      : items.map((l) => '${l.qty}x ${l.product.name}').join(', ');
  return ParsedOrder(
    items: items,
    total: total,
    pagoCon: pago,
    vuelto: vuelto,
    resumen: resumen,
  );
}

int _qtyForProduct(String text, Product p) {
  var best = 0;
  for (final alias in p.aliases) {
    final withNum = RegExp(
      r'(?:^|\s)(?:(\d+)|un|una|unos|unas)\s+' + RegExp.escape(alias) + r'\b',
    );
    var hit = 0;
    for (final m in withNum.allMatches(text)) {
      final g = m.group(1);
      hit += g != null ? (int.tryParse(g) ?? 1) : 1;
    }
    if (hit == 0) {
      final bare = RegExp(r'\b' + RegExp.escape(alias) + r'\b');
      if (bare.hasMatch(text)) hit = 1;
    }
    if (hit > best) best = hit;
  }
  return best;
}

double _extractPago(String text) {
  final patterns = [
    RegExp(r'pag(?:aron|ue|o)?\s+con\s+(?:uno\s+de\s+)?(\d+(?:[.,]\d+)?)'),
    RegExp(r'billete\s+de\s+(\d+(?:[.,]\d+)?)'),
    RegExp(r'con\s+(?:un\s+)?(?:billete\s+de\s+)?(\d+(?:[.,]\d+)?)'),
  ];
  for (final re in patterns) {
    final m = re.firstMatch(text);
    if (m != null) {
      return double.tryParse(m.group(1)!.replaceAll(',', '.')) ?? 0;
    }
  }
  return 0;
}

ParsedOrder parsedOrderFromJson(String raw, {bool fromAi = false}) {
  var s = raw.trim();
  if (s.startsWith('```')) {
    s = s
        .replaceAll(RegExp(r'^```(?:json)?'), '')
        .replaceAll(RegExp(r'```\s*\$'), '')
        .trim();
  }
  final map = jsonDecode(s) as Map<String, dynamic>;
  final items = <CartLine>[];
  final rawItems = map['items'] as List<dynamic>? ?? [];
  for (final it in rawItems) {
    final m = it as Map<String, dynamic>;
    final nombre = (m['nombre'] ?? '').toString().toLowerCase();
    final cant = (m['cant'] as num?)?.toInt() ?? 1;
    Product? match;
    for (final p in catalog) {
      if (p.name.toLowerCase() == nombre ||
          p.aliases.any((a) => nombre.contains(a))) {
        match = p;
        break;
      }
    }
    match ??= Product(
      'x',
      m['nombre'].toString(),
      (m['precio'] as num?)?.toDouble() ?? 0,
      const [],
    );
    if (cant > 0 && match.price > 0) {
      items.add(CartLine(match, cant));
    }
  }
  final total = (map['total'] as num?)?.toDouble() ??
      items.fold(0.0, (s, l) => s + l.lineTotal);
  final pago = (map['pago_con'] as num?)?.toDouble() ?? 0;
  final vuelto = (map['vuelto'] as num?)?.toDouble() ??
      (pago > 0 ? (pago - total).clamp(0, double.infinity).toDouble() : 0);
  return ParsedOrder(
    items: items,
    total: total,
    pagoCon: pago,
    vuelto: vuelto,
    resumen: (map['resumen'] ?? '').toString(),
    fromAi: fromAi,
  );
}
