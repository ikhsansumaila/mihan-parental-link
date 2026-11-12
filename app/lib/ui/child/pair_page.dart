import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../data/repo.dart';
import '../../platform/enforcer.dart';

class PairPage extends StatefulWidget {
  final VoidCallback onPaired;
  final VoidCallback onBack;
  const PairPage({super.key, required this.onPaired, required this.onBack});

  @override
  State<PairPage> createState() => _PairPageState();
}

class _PairPageState extends State<PairPage> {
  final _code = TextEditingController();
  bool _busy = false;
  String? _error;

  Future<void> _pair() async {
    final code = _code.text.replaceAll(RegExp(r'\D'), '');
    if (code.length != 6) {
      setState(() => _error = 'Kode harus 6 digit.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final id = await Repo.instance.pairWithCode(code, model: await Enforcer.model());
      await Enforcer.activate(id);
      widget.onPaired();
    } catch (e) {
      setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Scaffold(
      appBar: AppBar(leading: BackButton(onPressed: widget.onBack), title: const Text('Hubungkan HP anak')),
      body: SafeArea(
        child: ListView(padding: const EdgeInsets.all(24), children: [
          const Text('Minta orang tua menekan "Tambah HP anak" di aplikasi atau web OctaLink, '
              'lalu masukkan kode 6 digit yang muncul.'),
          const SizedBox(height: 24),
          TextField(
            controller: _code,
            autofocus: true,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(6)],
            textAlign: TextAlign.center,
            style: t.textTheme.headlineMedium?.copyWith(letterSpacing: 8),
            decoration: const InputDecoration(border: OutlineInputBorder(), hintText: '000000'),
            onSubmitted: (_) => _pair(),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!, style: TextStyle(color: t.colorScheme.error)),
          ],
          const SizedBox(height: 24),
          FilledButton(
            onPressed: _busy ? null : _pair,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: _busy
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Hubungkan'),
            ),
          ),
        ]),
      ),
    );
  }
}
