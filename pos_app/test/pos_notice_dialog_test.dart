import 'package:admin_panel_flutter/src/features/pos/presentation/pos_notice_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('successful operations do not open a notice dialog', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => showPosNotice(
              context,
              title: '操作成功',
              message: '已保存。',
              tone: PosNoticeTone.success,
            ),
            child: const Text('保存'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('pos-notice-dialog')), findsNothing);
  });

  testWidgets('notice tone is visible and announced', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => showPosNotice(
              context,
              title: '库存不足',
              message: '油边王库存仅剩 2 份。',
              tone: PosNoticeTone.warning,
            ),
            child: const Text('打开'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('pos-notice-dialog')), findsOneWidget);
    expect(find.byKey(const Key('pos-notice-tone')), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is Semantics && widget.properties.label == '操作警告：库存不足',
      ),
      findsOneWidget,
    );

    final tone = tester.widget<ColoredBox>(
      find.byKey(const Key('pos-notice-tone')),
    );
    expect(tone.color, const Color(0xffed9b2b));
  });

  testWidgets('long notice text stays readable in a scrollable body', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => showPosNotice(
              context,
              title: '操作失败',
              message: List.filled(8, '后厨打印机暂时无法连接').join('，'),
              tone: PosNoticeTone.error,
            ),
            child: const Text('打开'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('pos-notice-message-scroll')), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is Semantics && widget.properties.label == '操作失败：操作失败',
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
}
