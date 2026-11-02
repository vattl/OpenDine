String money(num? value) {
  if (value == null) return '-';
  return '￥${value.toStringAsFixed(2)}';
}

String dash(String? value) {
  if (value == null || value.trim().isEmpty) return '-';
  return value;
}
