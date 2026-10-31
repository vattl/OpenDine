import 'package:flutter_test/flutter_test.dart';
import 'package:kds_app/core/board/kds_fulfillment.dart';

void main() {
  test('resolves fulfillment channels from flags and backend labels', () {
    expect(
      KdsFulfillment.resolve({'dineInOrTakeOut': '堂食'}),
      KdsFulfillmentChannel.dineIn,
    );
    expect(
      KdsFulfillment.resolve({'takeout_flag': 1}),
      KdsFulfillmentChannel.takeout,
    );
    expect(
      KdsFulfillment.resolve({'fulfillment_type': 'self_pickup'}),
      KdsFulfillmentChannel.pickup,
    );
    expect(
      KdsFulfillment.resolve({'pack_flag': true}),
      KdsFulfillmentChannel.pack,
    );
  });

  test('explicit pickup label wins over a generic takeout flag', () {
    expect(
      KdsFulfillment.resolve({
        'dineInOrTakeOut': '到店自提',
        'takeout_flag': 1,
      }),
      KdsFulfillmentChannel.pickup,
    );
  });

  test('LAN canonical delivery stays distinct and input aliases normalize', () {
    expect(
      KdsFulfillment.resolve({'fulfillment_type': 'delivery'}),
      KdsFulfillmentChannel.delivery,
    );
    expect(
      KdsFulfillment.resolve({'fulfillment_type': 'takeaway'}),
      KdsFulfillmentChannel.takeout,
    );
    expect(
      KdsFulfillment.resolve({'fulfillment_type': 'self_pickup'}),
      KdsFulfillmentChannel.pickup,
    );
  });
}
