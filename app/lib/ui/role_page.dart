import 'package:flutter/material.dart';

class RolePage extends StatelessWidget {
  final void Function(String role) onPick;
  const RolePage({super.key, required this.onPick});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    Widget option(IconData icon, String title, String desc, String role) => Card(
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => onPick(role),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Row(children: [
                Icon(icon, size: 40, color: t.colorScheme.primary),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(title, style: t.textTheme.titleMedium),
                    const SizedBox(height: 4),
                    Text(desc, style: t.textTheme.bodyMedium),
                  ]),
                ),
                const Icon(Icons.chevron_right),
              ]),
            ),
          ),
        );

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: ListView(padding: const EdgeInsets.all(24), shrinkWrap: true, children: [
              Text('Mihan Parental Link', style: t.textTheme.displaySmall, textAlign: TextAlign.center),
              const SizedBox(height: 8),
              const Text('HP ini akan dipakai oleh siapa?', textAlign: TextAlign.center),
              const SizedBox(height: 32),
              option(Icons.supervisor_account, 'Orang tua', 'Atur jadwal & pantau HP anak.', 'parent'),
              const SizedBox(height: 12),
              option(Icons.child_care, 'Anak', 'HP ini akan diawasi dan dikunci sesuai jadwal.', 'child'),
            ]),
          ),
        ),
      ),
    );
  }
}
