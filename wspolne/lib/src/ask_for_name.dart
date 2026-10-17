import 'package:flutter/material.dart';

/// Okienko z polem tekstowym; zwraca wpisaną nazwę albo null po anulowaniu.
Future<String?> askForName(
  BuildContext context, {
  required String title,
  String initial = '',
  String? hint,
  int maxLength = 100,
}) {
  final controller = TextEditingController(text: initial);
  return showDialog<String>(
    context: context,
    builder: (ctx) {
      void submit() {
        final value = controller.text.trim();
        if (value.isNotEmpty) Navigator.pop(ctx, value);
      }

      return AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: maxLength,
          textCapitalization: TextCapitalization.sentences,
          decoration: InputDecoration(hintText: hint),
          onSubmitted: (_) => submit(),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Anuluj')),
          FilledButton(onPressed: submit, child: const Text('Zapisz')),
        ],
      );
    },
  );
}
