import 'dart:convert';

/// 从 spec_norm / taste_norm / selectedSpicy 等提取卡片可展示的规格文案
abstract final class KdsSpecText {
  static const _tasteKeys = {'辣度', '甜度', '温度', '口味'};

  static const _emptyValues = {
    '',
    '-',
    'default',
    'none',
    'null',
    '无',
    '无规格',
    '0',
  };

  /// 卡片展示：多规格值用英文逗号合并（如「不辣,9成熟,常温」），不含字段标题
  static String? display({
    String? specNorm,
    String? tasteNorm,
    List<Map<String, dynamic>> lines = const [],
    bool includeTaste = true,
  }) {
    final parts = <String>[];

    if (lines.isNotEmpty) {
      for (final line in lines) {
        _appendUnique(
            parts, collectLineValues(line, includeTaste: includeTaste));
      }
    } else {
      _appendUnique(
          parts, collectRawValues(specNorm, includeTaste: includeTaste));
      _appendUnique(
          parts, collectRawValues(tasteNorm, includeTaste: includeTaste));
    }

    return parts.isEmpty ? null : parts.join(',');
  }

  static List<String> collectLineValues(
    Map<String, dynamic> line, {
    bool includeTaste = true,
  }) {
    for (final key in const [
      'selectedSpicy',
      'selected_spicy',
      'specification',
      'spec_text',
      'spec_label',
    ]) {
      final parts =
          collectRawValues(line[key]?.toString(), includeTaste: includeTaste);
      if (parts.isNotEmpty) return parts;
    }

    final parts = <String>[];
    _appendUnique(
      parts,
      collectRawValues(
        line['spec_norm']?.toString() ?? line['specNorm']?.toString(),
        includeTaste: false,
      ),
    );
    if (includeTaste) {
      _appendUnique(
        parts,
        collectRawValues(
          line['taste_norm']?.toString() ??
              line['tasteNorm']?.toString() ??
              line['taste']?.toString(),
          includeTaste: true,
        ),
      );
    }
    return parts;
  }

  static List<String> collectRawValues(
    String? raw, {
    bool includeTaste = true,
    Set<String> tasteKeys = _tasteKeys,
  }) {
    final text = raw?.trim();
    if (text == null || text.isEmpty) return const [];

    if (text.startsWith('{') || text.startsWith('[')) {
      return _valuesFromJson(text,
          includeTaste: includeTaste, tasteKeys: tasteKeys);
    }

    final humanized = humanize(text);
    return humanized == null ? const [] : [humanized];
  }

  static String? fromLinesOnly(
    List<Map<String, dynamic>> lines, {
    bool includeTaste = false,
  }) {
    final parts = <String>[];
    for (final line in lines) {
      _appendUnique(parts, collectLineValues(line, includeTaste: includeTaste));
    }
    if (parts.isEmpty) return null;
    return parts.join(',');
  }

  static String? fromLine(
    Map<String, dynamic> line, {
    bool includeTaste = false,
  }) {
    final parts = collectLineValues(line, includeTaste: includeTaste);
    if (parts.isEmpty) return null;
    return parts.join(',');
  }

  static String? parseSelectedSpicy(String? raw, {bool includeTaste = false}) {
    final parts = collectRawValues(raw, includeTaste: includeTaste);
    if (parts.isEmpty) return null;
    return parts.join(',');
  }

  /// 解析 selectedSpicy / specification / JSON 规格（兼容旧调用）
  static String? parseOptionJson(
    String? raw, {
    bool includeTaste = false,
    Set<String> tasteKeys = _tasteKeys,
    bool specOnly = false,
    bool tasteOnly = false,
  }) {
    final parts = collectRawValues(
      raw,
      includeTaste: includeTaste && !specOnly || tasteOnly,
      tasteKeys: tasteKeys,
    );
    if (specOnly) {
      final specParts = _valuesFromJson(
        raw,
        includeTaste: false,
        tasteKeys: tasteKeys,
        specOnly: true,
      );
      if (specParts.isEmpty) return null;
      return specParts.join(',');
    }
    if (tasteOnly) {
      final tasteParts = _valuesFromJson(
        raw,
        includeTaste: true,
        tasteKeys: tasteKeys,
        tasteOnly: true,
      );
      if (tasteParts.isEmpty) return null;
      return tasteParts.join(',');
    }
    if (parts.isEmpty) return null;
    return parts.join(',');
  }

  static List<String> _valuesFromJson(
    String? raw, {
    required bool includeTaste,
    Set<String> tasteKeys = _tasteKeys,
    bool specOnly = false,
    bool tasteOnly = false,
  }) {
    final text = raw?.trim();
    if (text == null || text.isEmpty) return const [];

    if (!text.startsWith('{') && !text.startsWith('[')) {
      final humanized = humanize(text);
      return humanized == null ? const [] : [humanized];
    }

    try {
      final decoded = jsonDecode(text);
      if (decoded is Map) {
        final parts = <String>[];
        for (final entry in decoded.entries) {
          final key = entry.key.toString();
          final isTaste = tasteKeys.contains(key);
          if (specOnly && isTaste) continue;
          if (tasteOnly && !isTaste) continue;
          if (!includeTaste && isTaste) continue;
          _appendUnique(parts, _valuesFromDynamic(entry.value));
        }
        return parts;
      }
      if (decoded is List) {
        return _valuesFromDynamic(decoded);
      }
    } catch (_) {}

    final fallback = humanize(text);
    return fallback == null ? const [] : [fallback];
  }

  static List<String> _valuesFromDynamic(dynamic value) {
    if (value == null) return const [];
    if (value is List) {
      final parts = <String>[];
      for (final item in value) {
        _appendUnique(parts, _valuesFromDynamic(item));
      }
      return parts;
    }
    final humanized = humanize(value.toString());
    return humanized == null ? const [] : [humanized];
  }

  static void _appendUnique(List<String> target, Iterable<String> values) {
    for (final value in values) {
      if (value.isEmpty) continue;
      if (!target.contains(value)) target.add(value);
    }
  }

  static String? humanize(
    String? raw, {
    Set<String> tasteKeys = _tasteKeys,
    bool specOnly = false,
    bool tasteOnly = false,
  }) {
    final text = raw?.trim();
    if (text == null || text.isEmpty) return null;
    if (_emptyValues.contains(text.toLowerCase())) return null;
    if (_looksLikeInternalKey(text)) return null;

    if (text.startsWith('{') || text.startsWith('[')) {
      final parts = _valuesFromJson(
        text,
        includeTaste: !specOnly,
        tasteKeys: tasteKeys,
        specOnly: specOnly,
        tasteOnly: tasteOnly,
      );
      if (parts.isEmpty) return null;
      return parts.join(',');
    }
    return text;
  }

  static bool isHumanReadable(String? raw) {
    final text = raw?.trim();
    if (text == null || text.isEmpty) return false;
    if (_emptyValues.contains(text.toLowerCase())) return false;
    if (_looksLikeInternalKey(text)) return false;
    if (text.startsWith('{')) {
      return collectRawValues(text).isNotEmpty;
    }
    return true;
  }

  static bool _looksLikeInternalKey(String text) {
    if (text.length >= 24 &&
        RegExp(r'^[a-f0-9]+$').hasMatch(text.toLowerCase())) {
      return true;
    }
    if (RegExp(r'^[a-f0-9]{8,}$', caseSensitive: false).hasMatch(text) &&
        !RegExp(r'[\u4e00-\u9fff]').hasMatch(text)) {
      return true;
    }
    return false;
  }

  /// 从组 + 明细汇总规格/口味键（mapper 用）
  static String? resolveGroupSpec(
    Map<String, dynamic> group,
    List<Map<String, dynamic>> lines,
  ) =>
      _resolveField(
        group,
        lines,
        field: 'spec_norm',
        spicyMode: _SpicyMode.specOnly,
      );

  static String? resolveGroupTaste(
    Map<String, dynamic> group,
    List<Map<String, dynamic>> lines,
  ) =>
      _resolveField(
        group,
        lines,
        field: 'taste_norm',
        spicyMode: _SpicyMode.tasteOnly,
      );

  static String? _resolveField(
    Map<String, dynamic> group,
    List<Map<String, dynamic>> lines, {
    required String field,
    required _SpicyMode spicyMode,
  }) {
    final fromGroup = group[field]?.toString();
    if (isHumanReadable(fromGroup)) return fromGroup!.trim();

    for (final line in lines) {
      final fromLineField = line[field]?.toString();
      if (isHumanReadable(fromLineField)) return fromLineField!.trim();
    }

    for (final line in lines) {
      for (final key in const [
        'selectedSpicy',
        'selected_spicy',
        'specification'
      ]) {
        final raw = line[key]?.toString();
        final parsed = switch (spicyMode) {
          _SpicyMode.specOnly => parseOptionJson(raw, specOnly: true),
          _SpicyMode.tasteOnly => parseOptionJson(raw, tasteOnly: true),
          _SpicyMode.all => parseOptionJson(raw, includeTaste: true),
        };
        if (parsed != null) return parsed;
      }
    }
    return null;
  }
}

enum _SpicyMode { specOnly, tasteOnly, all }
