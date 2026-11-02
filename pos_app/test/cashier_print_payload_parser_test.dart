import 'package:flutter_test/flutter_test.dart';

import 'package:admin_panel_flutter/src/features/cashier_settings/domain/print_payload_parser.dart';
import 'package:admin_panel_flutter/src/features/cashier_settings/domain/receipt_preview_models.dart';

/// 打印任务 payload 解析器测试：标签语义按飞鹅云解析规则
/// （CB/B/C/RIGHT/BOLD/L/W/BR/CUT/LOGO/QR/BC/AUDIO/空行/分割线），
/// <B> 放大一倍、<BOLD> 加粗、非官方标签（DB/R）按普通文本。
void main() {
  group('parsePrintPayloadElements', () {
    test('空输入返回空列表', () {
      expect(parsePrintPayloadElements(''), isEmpty);
      expect(parsePrintPayloadElements('   '), isEmpty);
    });

    test('<CB> 解析为居中加粗双倍大标题（header 无 meta，倍率由 size=DOUBLE 表达）', () {
      final els = parsePrintPayloadElements('<CB>传菜单 20号</CB>');
      expect(els, hasLength(1));
      final el = els.first;
      expect(el.type, PrintElementType.header);
      expect(el.text, '传菜单 20号');
      expect(el.align, PrintElementAlign.center);
      expect(el.bold, isTrue);
      expect(el.size, PrintElementSize.double);
      // 与后端一致：header 元素不携带缩放 meta
      expect(el.meta, isEmpty);
    });

    test('<DB>（非飞鹅标签）不赋予特殊格式，按普通文本解析', () {
      final el = parsePrintPayloadElements('<DB>欢迎光临</DB>').single;
      expect(el.type, PrintElementType.text);
      expect(el.size, PrintElementSize.normal);
      expect(el.align, PrintElementAlign.left);
      expect(el.bold, isFalse);
      expect(el.text, '欢迎光临');
    });

    test('<C> 居中普通文本', () {
      final el = parsePrintPayloadElements('<C>居中内容</C>').single;
      expect(el.type, PrintElementType.text);
      expect(el.align, PrintElementAlign.center);
      expect(el.bold, isFalse);
      expect(el.size, PrintElementSize.normal);
    });

    test('<RIGHT> 右对齐', () {
      final el = parsePrintPayloadElements('<RIGHT>右对齐内容</RIGHT>').single;
      expect(el.align, PrintElementAlign.right);
      expect(el.text, '右对齐内容');
    });

    test('<B> 按飞鹅规则为「放大一倍」（double 尺寸，非加粗）；<BOLD> 才加粗', () {
      final b = parsePrintPayloadElements('<B>合计：¥60</B>').single;
      expect(b.type, PrintElementType.header);
      expect(b.size, PrintElementSize.double);
      expect(b.align, PrintElementAlign.left);
      expect(b.bold, isFalse);
      expect(b.text, '合计：¥60');

      final bold = parsePrintPayloadElements('<BOLD>粗</BOLD>').single;
      expect(bold.bold, isTrue);
      expect(bold.size, PrintElementSize.normal);
    });

    test('<L>/<W> 倍高倍宽写入 meta（仅 TEXT 元素）', () {
      final el = parsePrintPayloadElements('<L>高字</L>').single;
      expect(el.type, PrintElementType.text);
      expect(el.meta['heightScale'], 2);
      expect(el.meta['widthScale'], isNot(2));

      final el2 = parsePrintPayloadElements('<W>宽字</W>').single;
      expect(el2.meta['widthScale'], 2);
      expect(el2.meta['heightScale'], isNot(2));

      // 普通行不携带缩放 meta（构造默认 {}）
      final plain = parsePrintPayloadElements('普通行').single;
      expect(plain.meta, isEmpty);
    });

    test('<BR> 与真实换行分行，且保留空格缩进', () {
      final els = parsePrintPayloadElements(
        '<CB>标题</CB><BR>油 边 王(不辣)    1<BR>备注：少辣',
      );
      expect(els, hasLength(3));
      expect(els[0].text, '标题');
      expect(els[1].text, '油 边 王(不辣)    1');
      expect(els[2].text, '备注：少辣');
    });

    test('<CUT> 解析为切刀节点（规范化分隔后前后各保留一个空行，与后端一致）', () {
      final els = parsePrintPayloadElements('<CUT>');
      expect(els, hasLength(3));
      expect(els[0].type, PrintElementType.text);
      expect(els[0].text, isEmpty);
      expect(els[1].type, PrintElementType.cut);
      expect(els[2].type, PrintElementType.text);
    });

    test('<LOGO>/<PLUGIN>/<AUDIO> 原生指令节点', () {
      PrintElement elOf(String payload, PrintElementType type) =>
          parsePrintPayloadElements(payload).firstWhere((e) => e.type == type);

      expect(elOf('<LOGO>', PrintElementType.logo).type, PrintElementType.logo);
      expect(
        elOf('<PLUGIN>', PrintElementType.cashDrawer).type,
        PrintElementType.cashDrawer,
      );
      final audio = elOf('<AUDIO-MT>', PrintElementType.audio);
      expect(audio.type, PrintElementType.audio);
      expect(audio.text, '<AUDIO-MT>');
    });

    test('<QR> 二维码节点', () {
      final el = parsePrintPayloadElements(
        '<QR>https://example.com/q</QR>',
      ).single;
      expect(el.type, PrintElementType.qrcode);
      expect(el.text, 'https://example.com/q');
      expect(el.align, PrintElementAlign.center);
    });

    test('<BC128_C> 条形码节点', () {
      final el = parsePrintPayloadElements(
        '<BC128_C>89012345</BC128_C>',
      ).single;
      expect(el.type, PrintElementType.barcode);
      expect(el.text, '89012345');
      expect(el.meta['mode'], 'BC128_C');
    });

    test('空行保留为 text 空元素', () {
      final els = parsePrintPayloadElements('第一行<BR><BR>第三行');
      expect(els, hasLength(3));
      expect(els[1].type, PrintElementType.text);
      expect(els[1].text, isEmpty);
    });

    test('分割线识别为 DIVIDER', () {
      final el = parsePrintPayloadElements(
        '--------------------------------',
      ).single;
      expect(el.type, PrintElementType.divider);
      expect(el.align, PrintElementAlign.center);
      // 短横线不够 4 个时按普通文本
      final plain = parsePrintPayloadElements('--').single;
      expect(plain.type, PrintElementType.text);
    });

    test('真实传菜单 payload 整体解析（与后端相同：CUT 前后各一个空行）', () {
      const payload =
          '<CB>传菜单 20号</CB><BR>'
          '<B>油 边 王(不辣)    1</B><BR>'
          '--------------------------------<BR>'
          '<BR>'
          '<C>堂食</C><BR>'
          '<CUT>';
      final els = parsePrintPayloadElements(payload);
      expect(els, hasLength(8));
      expect(els[0].type, PrintElementType.header);
      expect(els[0].text, '传菜单 20号');
      expect(els[1].type, PrintElementType.header);
      expect(els[1].text, '油 边 王(不辣)    1');
      expect(els[1].size, PrintElementSize.double);
      expect(els[1].bold, isFalse);
      expect(els[2].type, PrintElementType.divider);
      expect(els[3].type, PrintElementType.text);
      expect(els[3].text, isEmpty);
      expect(els[4].text, '堂食');
      expect(els[4].align, PrintElementAlign.center);
      expect(els[5].type, PrintElementType.text);
      expect(els[5].text, isEmpty);
      expect(els[6].type, PrintElementType.cut);
      expect(els[7].type, PrintElementType.text);
      expect(els[7].text, isEmpty);
    });
  });

  group('printPayloadToPlainText', () {
    test('去标签、BR 换行、CUT 空行（与后端 toPlainText 一致：<BR><CUT> 共 3 个换行）', () {
      const raw = '<CB>传菜单</CB><BR>油边王   1<BR><CUT>';
      expect(printPayloadToPlainText(raw), '传菜单\n油边王   1\n\n\n');
    });

    test('空输入返回空串', () {
      expect(printPayloadToPlainText(''), '');
      expect(printPayloadToPlainText('   '), '');
    });
  });
}
