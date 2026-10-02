import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:storeflow_pos/core/theme/app_theme.dart';
import 'package:storeflow_pos/core/theme/theme_settings.dart';
import 'package:storeflow_pos/core/ui/ui_kit.dart';
import 'package:storeflow_pos/features/products/presentation/product_editor.dart';

void main() {
  Widget host(Widget child) => MaterialApp(
    theme: AppTheme.light(const ThemeSettings()),
    home: Scaffold(
      body: Center(child: SizedBox(width: 320, child: child)),
    ),
  );

  testWidgets('AppSelect follows value changes from its parent', (
    tester,
  ) async {
    final value = ValueNotifier<String?>('a');
    String? picked;
    await tester.pumpWidget(
      host(
        ValueListenableBuilder<String?>(
          valueListenable: value,
          builder: (_, current, _) => AppSelect<String?>(
            label: 'Letter',
            value: current,
            items: const [
              SelectItem(null, 'None'),
              SelectItem('a', 'Alpha'),
              SelectItem('b', 'Bravo'),
            ],
            onChanged: (v) => picked = v,
          ),
        ),
      ),
    );
    expect(find.widgetWithText(TextField, 'Alpha'), findsOneWidget);

    // A reload from outside (e.g. Discard) must update the visible text;
    // DropdownButtonFormField used to keep showing the old choice.
    value.value = 'b';
    await tester.pump();
    expect(find.widgetWithText(TextField, 'Bravo'), findsOneWidget);
    value.value = null;
    await tester.pump();
    expect(find.widgetWithText(TextField, 'None'), findsOneWidget);

    await tester.tap(find.byType(TextField));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Alpha').last);
    await tester.pumpAndSettle();
    expect(picked, 'a');
  });

  testWidgets('AppSegmented reports taps', (tester) async {
    var selected = 1;
    await tester.pumpWidget(
      host(
        StatefulBuilder(
          builder: (context, setState) => AppSegmented<int>(
            value: selected,
            items: const [SegmentItem(1, 'One'), SegmentItem(2, 'Two')],
            onChanged: (v) => setState(() => selected = v),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Two'));
    await tester.pumpAndSettle();
    expect(selected, 2);
  });

  test('date presets and labels', () {
    final today = DatePreset.today.range;
    expect(today.start, today.end);
    expect(describeRange(today), 'Today');
    expect(describeRange(null), 'All dates');
    final week = DatePreset.last7.range;
    expect(week.end.difference(week.start).inDays, 6);
  });

  test('EAN-13 check digits and in-store generator', () {
    expect(ean13CheckDigit('896400012345'), 4);
    expect(ean13CheckDigit('400638133393'), 1); // 4006381333931
    for (var i = 0; i < 50; i++) {
      final code = generateInStoreEan13();
      expect(code, matches(RegExp(r'^2\d{12}$')));
      expect(ean13CheckDigit(code.substring(0, 12)), int.parse(code[12]));
    }
  });
}
