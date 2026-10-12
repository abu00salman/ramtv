import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ramtv/ui/dpad.dart';
import 'package:ramtv/ui/widgets.dart';

void main() {
  testWidgets('TV select activates focused cards in RTL', (tester) async {
    var activated = 0;
    await tester.pumpWidget(MaterialApp(
      home: Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(
            body: Pressable(
          onTap: () => activated++,
          child: const Text('قناة'),
        )),
      ),
    ));
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pump();
    expect(activated, 1);
  });

  testWidgets('down leaves server field and reaches the submit button',
      (tester) async {
    final controller = TextEditingController();
    var activated = false;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
          body: Column(children: [
        DpadTextField(
          autofocus: true,
          controller: controller,
          decoration: const InputDecoration(labelText: 'Server'),
        ),
        FilledButton(
            onPressed: () => activated = true, child: const Text('Add')),
      ])),
    ));
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(activated, isTrue);
    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
  });
}
