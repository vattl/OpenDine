import 'receipt_preview_models.dart';

/// 将打印任务历史 payload（飞鹅/ESC-POS 标签文本）解析为结构化元素列表。
///
/// 标签语义严格按飞鹅云解析规则：`<BR>` 换行 / `<CUT>` 切刀 / `<LOGO>` / `<PLUGIN>` /
/// `<CB>` 居中放大 / `<B>` 放大一倍 / `<C>` 居中 / `<L>` 变高一倍 / `<W>` 变宽一倍 /
/// `<QR>` 二维码 / `<RIGHT>` 右对齐 / `<BOLD>` 加粗 / `<BC128_*>` 条形码 / `<AUDIO-*>` 语音。
/// 注意：`<B>` 为「放大一倍」而非加粗（加粗仅 `<BOLD>`）；非官方标签（如 `<DB>`、`<R>`）
/// 不赋予特殊格式，按普通文本解析，保证「打印任务记录 → 查看打印内容」预览与真实
/// 飞鹅设备出票一比一。
List<PrintElement> parsePrintPayloadElements(String rawContent) {
  final elements = <PrintElement>[];
  final text = rawContent;
  if (text.trim().isEmpty) return elements;

  // 兼容 <BR> 与真实换行符；相邻原生控制指令用 <BR> 分隔（仅 AST 用）
  var normalized = text.replaceAll('\r\n', '<BR>').replaceAll('\n', '<BR>');
  normalized = normalized.replaceAllMapped(
    RegExp(
      r'<(LOGO|PLUGIN|CUT|AUDIO-(?:COMMON|MT|ELE|JD|CANCEL|REFUND))>',
      caseSensitive: false,
    ),
    (m) => '<BR><${m[1]}><BR>',
  );
  final lines = normalized.split(RegExp(r'<BR>', caseSensitive: false));

  for (final rawLine in lines) {
    final trimmed = rawLine.trim();

    // 1. 设备原生指令：LOGO / 钱箱 / 音频。这些不是可见文本，仍作为节点返回，
    // 否则预览会错误地宣称设备将执行一个不存在的动作。
    if (trimmed.toLowerCase() == '<logo>') {
      elements.add(
        const PrintElement(
          type: PrintElementType.logo,
          align: PrintElementAlign.center,
        ),
      );
      continue;
    }
    if (trimmed.toLowerCase() == '<plugin>') {
      elements.add(const PrintElement(type: PrintElementType.cashDrawer));
      continue;
    }
    final audioMatch = RegExp(
      r'<AUDIO-(COMMON|MT|ELE|JD|CANCEL|REFUND)>',
      caseSensitive: false,
    ).firstMatch(trimmed);
    if (audioMatch != null &&
        audioMatch.start == 0 &&
        audioMatch.end == trimmed.length) {
      elements.add(
        PrintElement(type: PrintElementType.audio, text: trimmed.toUpperCase()),
      );
      continue;
    }

    // 2. 二维码标签
    final qrMatch = RegExp(
      r'<(QR|qrcode)>(.*?)</(QR|qrcode)>',
      caseSensitive: false,
    ).firstMatch(trimmed);
    if (qrMatch != null) {
      elements.add(
        PrintElement(
          type: PrintElementType.qrcode,
          text: qrMatch.group(2),
          align: PrintElementAlign.center,
        ),
      );
      continue;
    }

    // 3. 条形码标签
    final bcMatch = RegExp(
      r'<(BC128_A|BC128_B|BC128_C|BC|BC128_Auto|barcode)>(.*?)</\1>',
      caseSensitive: false,
    ).firstMatch(trimmed);
    if (bcMatch != null) {
      elements.add(
        PrintElement(
          type: PrintElementType.barcode,
          text: bcMatch.group(2),
          align: PrintElementAlign.center,
          meta: {'mode': bcMatch.group(1)!.toUpperCase()},
        ),
      );
      continue;
    }

    // 4. 切刀指令
    if (trimmed.toLowerCase() == '<cut>') {
      elements.add(const PrintElement(type: PrintElementType.cut));
      continue;
    }

    // 5. 解析行样式（加粗、居中、居右、倍宽倍高）——严格按飞鹅云标签规则：
    //    <CB> 居中放大 / <B> 放大一倍（非加粗） / <C> 居中 / <RIGHT> 右对齐 /
    //    <BOLD> 加粗 / <L> 字体变高一倍 / <W> 字体变宽一倍。
    final upper = rawLine.toUpperCase();
    var bold = false;
    var size = PrintElementSize.normal;
    var align = PrintElementAlign.left;

    if (upper.contains('<CB>')) {
      bold = true;
      size = PrintElementSize.double;
      align = PrintElementAlign.center;
    } else if (upper.contains('<C>')) {
      align = PrintElementAlign.center;
    } else if (upper.contains('<RIGHT>')) {
      align = PrintElementAlign.right;
    }

    if (upper.contains('<B>')) {
      // 飞鹅：<B> 为「放大一倍」（倍宽倍高），不是加粗；加粗仅由 <BOLD> 触发。
      size = PrintElementSize.double;
    }
    if (upper.contains('<BOLD>')) {
      bold = true;
    }

    var heightScale = upper.contains('<L>') ? 2 : 1;
    var widthScale = upper.contains('<W>') ? 2 : 1;
    if (upper.contains('<CB>')) {
      heightScale = 2;
      widthScale = 2;
    }

    // 提取纯文本内容，保留空格与缩进（保证真实排版一模一样）
    var cleanText = rawLine.replaceAll(RegExp(r'<[^>]+>'), '');
    if (cleanText.endsWith('\r')) {
      cleanText = cleanText.substring(0, cleanText.length - 1);
    }

    // 空行保留（保证换行间距 100% 一致）
    if (cleanText.isEmpty) {
      elements.add(
        _styledText('', align, false, PrintElementSize.normal, 1, 1),
      );
      continue;
    }

    // 分割线判定
    final testDivider = cleanText.trim();
    if (testDivider.length >= 4 &&
        RegExp(r'^[-=*#_─~]+$').hasMatch(testDivider)) {
      elements.add(
        PrintElement(
          type: PrintElementType.divider,
          text: cleanText,
          align: PrintElementAlign.center,
        ),
      );
      continue;
    }

    // 大标题判定（DOUBLE / LARGE）
    if (size == PrintElementSize.double || size == PrintElementSize.large) {
      elements.add(
        PrintElement(
          type: PrintElementType.header,
          text: cleanText,
          align: align,
          bold: bold,
          size: size,
        ),
      );
      continue;
    }

    // 默认普通文本行
    elements.add(
      _styledText(cleanText, align, bold, size, heightScale, widthScale),
    );
  }

  return elements;
}

/// 与后端 `PrintTicketParser.toPlainText` 对齐：去标签、<BR>→换行、<CUT>→空行。
String printPayloadToPlainText(String rawContent) {
  final text = rawContent;
  if (text.trim().isEmpty) return '';
  var t = text
      .replaceAll('<BR>', '\n')
      .replaceAll('<br>', '\n')
      .replaceAll('<CUT>', '\n\n')
      .replaceAll('<cut>', '\n\n');
  return t.replaceAll(RegExp(r'<[^>]+>'), '');
}

PrintElement _styledText(
  String text,
  PrintElementAlign align,
  bool bold,
  PrintElementSize size,
  int heightScale,
  int widthScale,
) {
  if (heightScale != 1 || widthScale != 1) {
    return PrintElement(
      type: PrintElementType.text,
      text: text,
      align: align,
      bold: bold,
      size: size,
      meta: {'heightScale': heightScale, 'widthScale': widthScale},
    );
  }
  return PrintElement(
    type: PrintElementType.text,
    text: text,
    align: align,
    bold: bold,
    size: size,
  );
}
