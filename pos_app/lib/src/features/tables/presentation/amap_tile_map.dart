const String amapRoadTileUrlTemplate =
    'https://webrd0{s}.is.autonavi.com/appmaptile'
    '?lang=zh_cn&size=1&scale=1&style=8&x={x}&y={y}&z={z}';

const List<String> amapRoadTileSubdomains = ['1', '2', '3', '4'];

Uri buildAmapRoadTileUri({
  required String subdomain,
  required int x,
  required int y,
  required int z,
}) => Uri.parse(
  amapRoadTileUrlTemplate
      .replaceAll('{s}', subdomain)
      .replaceAll('{x}', '$x')
      .replaceAll('{y}', '$y')
      .replaceAll('{z}', '$z'),
);
