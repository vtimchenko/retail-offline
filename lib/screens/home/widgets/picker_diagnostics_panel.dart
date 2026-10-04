// TEMPORARY DIAGNOSTICS PANEL for the iOS local-file-picker investigation.
// Delete together with `lib/diagnostics/` once the problem is fixed.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../diagnostics/picker_diagnostics.dart';

class PickerDiagnosticsPanel extends StatefulWidget {
  const PickerDiagnosticsPanel({super.key});

  @override
  State<PickerDiagnosticsPanel> createState() => _PickerDiagnosticsPanelState();
}

class _PickerDiagnosticsPanelState extends State<PickerDiagnosticsPanel> {
  final ScrollController _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _copy(PickerDiagnostics diag) async {
    final messenger = ScaffoldMessenger.of(context);
    await Clipboard.setData(ClipboardData(text: diag.text));
    messenger.showSnackBar(const SnackBar(content: Text('Лог скопійовано')));
  }

  @override
  Widget build(BuildContext context) {
    final diag = PickerDiagnostics.instance;
    return Card(
      key: const Key('picker-diagnostics'),
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'iOS File Picker Diagnostics (тимчасово)',
              style: Theme.of(context).textTheme.titleSmall
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Container(
              height: 260,
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.black,
                borderRadius: BorderRadius.circular(6),
              ),
              child: ListenableBuilder(
                listenable: diag,
                builder: (context, _) {
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (_scroll.hasClients) {
                      _scroll.jumpTo(_scroll.position.maxScrollExtent);
                    }
                  });
                  return Scrollbar(
                    controller: _scroll,
                    child: SingleChildScrollView(
                      controller: _scroll,
                      child: SizedBox(
                        width: double.infinity,
                        child: SelectableText(
                          diag.lines.isEmpty
                              ? 'Лог порожній. Натисніть «Обрати файл».'
                              : diag.text,
                          key: const Key('picker-diagnostics-log'),
                          style: const TextStyle(
                            color: Colors.greenAccent,
                            fontFamily: 'monospace',
                            fontSize: 11,
                            height: 1.35,
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton(
                  key: const Key('picker-diagnostics-clear'),
                  onPressed: diag.clear,
                  child: const Text('Очистити лог'),
                ),
                OutlinedButton(
                  key: const Key('picker-diagnostics-copy'),
                  onPressed: () => _copy(diag),
                  child: const Text('Копіювати'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
