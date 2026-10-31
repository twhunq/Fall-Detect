import 'package:bao_nga_iot/core/fusion/alert_fusion_engine.dart';
import 'package:bao_nga_iot/core/fusion/alert_models.dart';
import 'package:flutter_test/flutter_test.dart';

final t0 = DateTime(2026, 1, 1, 12);

AlertSignal sig(
  AlertOrigin origin,
  AlertChannel channel,
  AlertKind kind,
  int seconds, {
  double? metric,
  DateTime? deviceTime,
  int? seq,
}) =>
    AlertSignal(
      origin: origin,
      channel: channel,
      kind: kind,
      deviceId: origin == AlertOrigin.camera ? 'CBC-7A3F91' : 'baonga-01',
      receivedAt: t0.add(Duration(seconds: seconds)),
      metric: metric,
      deviceTime: deviceTime,
      seq: seq,
    );

void main() {
  test('camera BLE + UDP repeats -> one ring', () {
    final e = AlertFusionEngine();
    var rings = 0;
    final signals = [
      sig(AlertOrigin.camera, AlertChannel.ble, AlertKind.fall, 0, metric: 0.9),
      sig(AlertOrigin.camera, AlertChannel.udp, AlertKind.fall, 0),
      sig(AlertOrigin.camera, AlertChannel.udp, AlertKind.fall, 1),
      sig(AlertOrigin.camera, AlertChannel.udp, AlertKind.fall, 2),
    ];
    for (final s in signals) {
      if (e.ingest(s).shouldRing) rings++;
    }
    expect(rings, 1);
    expect(e.recent, hasLength(1));
    expect(e.recent.first.arrivals.keys, containsAll([AlertChannel.ble, AlertChannel.udp]));
    expect(e.recent.first.cameraConfidence, 0.9);
    expect(e.recent.first.label, 'TÉ NGÃ — Camera AI');
  });

  test('wearable UDP then cloud then LAN -> one ring, 3 arrivals', () {
    final e = AlertFusionEngine();
    final r1 = e.ingest(sig(AlertOrigin.wearable, AlertChannel.udp, AlertKind.fall, 0, metric: 3.2));
    final r2 = e.ingest(sig(AlertOrigin.wearable, AlertChannel.cloud, AlertKind.fall, 2,
        deviceTime: t0.subtract(const Duration(milliseconds: 500))));
    final r3 = e.ingest(sig(AlertOrigin.wearable, AlertChannel.lan, AlertKind.fall, 3));
    expect(r1.shouldRing, isTrue);
    expect(r2.action, FusionAction.duplicate);
    expect(r3.action, FusionAction.duplicate);
    final i = e.recent.single;
    expect(i.arrivals.keys.toSet(),
        {AlertChannel.udp, AlertChannel.cloud, AlertChannel.lan});
    expect(i.firstChannel, AlertChannel.udp);
    expect(i.impactG, 3.2);
    expect(i.arrivals[AlertChannel.cloud], const Duration(seconds: 2));
    expect(i.cloudLatency, const Duration(milliseconds: 2500));
    expect(i.label, 'TÉ NGÃ — Vòng đeo');
  });

  test('wearable + camera within 30 s -> fused, no second ring', () {
    final e = AlertFusionEngine();
    expect(e.ingest(sig(AlertOrigin.wearable, AlertChannel.udp, AlertKind.fall, 0)).shouldRing, isTrue);
    final r = e.ingest(sig(AlertOrigin.camera, AlertChannel.ble, AlertKind.fall, 30));
    expect(r.action, FusionAction.fused);
    expect(r.shouldRing, isFalse);
    expect(r.incident.multiSource, isTrue);
    expect(r.incident.label, 'ĐA NGUỒN XÁC NHẬN (Vòng đeo + Camera AI)');
    expect(r.incident.deviceIds.keys.toSet(), {AlertOrigin.wearable, AlertOrigin.camera});
    // Bản sao tiếp theo của camera vẫn là trùng lặp.
    expect(e.ingest(sig(AlertOrigin.camera, AlertChannel.udp, AlertKind.fall, 31)).action,
        FusionAction.duplicate);
    expect(e.recent, hasLength(1));
  });

  test('31 s apart -> two rings', () {
    final e = AlertFusionEngine();
    expect(e.ingest(sig(AlertOrigin.wearable, AlertChannel.udp, AlertKind.fall, 0)).shouldRing, isTrue);
    expect(e.ingest(sig(AlertOrigin.camera, AlertChannel.udp, AlertKind.fall, 31)).shouldRing, isTrue);
    expect(e.recent, hasLength(2));
  });

  test('same origin after dedupe window rings again', () {
    final e = AlertFusionEngine();
    expect(e.ingest(sig(AlertOrigin.wearable, AlertChannel.udp, AlertKind.fall, 0)).shouldRing, isTrue);
    expect(e.ingest(sig(AlertOrigin.wearable, AlertChannel.udp, AlertKind.fall, 61)).shouldRing, isTrue);
  });

  test('acknowledged then late cloud copy -> no ring', () {
    final e = AlertFusionEngine(clock: () => t0.add(const Duration(seconds: 5)));
    final r = e.ingest(sig(AlertOrigin.wearable, AlertChannel.udp, AlertKind.fall, 0));
    final acked = e.acknowledge(r.incident.id)!;
    expect(acked.acknowledged, isTrue);
    expect(acked.acknowledgedAt, t0.add(const Duration(seconds: 5)));
    final late = e.ingest(sig(AlertOrigin.wearable, AlertChannel.cloud, AlertKind.fall, 6));
    expect(late.shouldRing, isFalse);
    expect(late.action, FusionAction.duplicate);
    expect(e.acknowledge('khong-co'), isNull);
  });

  test('inactive dedupes, resumed resolves it', () {
    final e = AlertFusionEngine();
    final a = e.ingest(sig(AlertOrigin.wearable, AlertChannel.cloud, AlertKind.inactive, 0, metric: 60));
    expect(a.shouldRing, isTrue);
    expect(e.ingest(sig(AlertOrigin.wearable, AlertChannel.udp, AlertKind.inactive, 3)).action,
        FusionAction.duplicate);
    expect(a.incident.stillMinutes, 60);
    expect(a.incident.label, 'BẤT ĐỘNG KÉO DÀI');

    final r = e.ingest(sig(AlertOrigin.wearable, AlertChannel.udp, AlertKind.resumed, 600));
    expect(r.action, FusionAction.info);
    expect(r.shouldRing, isFalse);
    expect(r.incident.label, 'ĐÃ CỬ ĐỘNG LẠI');
    expect(a.incident.acknowledged, isTrue);
    expect(e.ingest(sig(AlertOrigin.wearable, AlertChannel.cloud, AlertKind.resumed, 602)).action,
        FusionAction.duplicate);

    // Bất động mới sau khi đã cử động lại phải đổ chuông.
    expect(e.ingest(sig(AlertOrigin.wearable, AlertChannel.udp, AlertKind.inactive, 640)).shouldRing,
        isTrue);
  });

  test('inactive does not fuse across origins', () {
    final e = AlertFusionEngine();
    e.ingest(sig(AlertOrigin.wearable, AlertChannel.udp, AlertKind.inactive, 0));
    expect(e.ingest(sig(AlertOrigin.camera, AlertChannel.udp, AlertKind.inactive, 1)).shouldRing,
        isTrue);
  });

  test('keeps at most 200 incidents', () {
    final e = AlertFusionEngine();
    for (var i = 0; i < 230; i++) {
      e.ingest(sig(AlertOrigin.wearable, AlertChannel.udp, AlertKind.fall, i * 100));
    }
    expect(e.recent, hasLength(200));
  });

  test('genuine second fall after ack (new UDP seq) rings', () {
    var now = t0;
    final e = AlertFusionEngine(clock: () => now);
    final r1 = e.ingest(sig(AlertOrigin.wearable, AlertChannel.udp, AlertKind.fall, 0, seq: 5));
    expect(r1.shouldRing, isTrue);
    e.acknowledge(r1.incident.id);
    final r2 = e.ingest(sig(AlertOrigin.wearable, AlertChannel.udp, AlertKind.fall, 30, seq: 6));
    expect(r2.shouldRing, isTrue);
    expect(e.recent, hasLength(2));
  });

  test('acknowledged: late copy dedupes, later edge rings', () {
    var now = t0.add(const Duration(seconds: 5));
    final e = AlertFusionEngine(clock: () => now);
    final r1 = e.ingest(sig(AlertOrigin.wearable, AlertChannel.udp, AlertKind.fall, 0, seq: 5));
    e.acknowledge(r1.incident.id);
    expect(e.ingest(sig(AlertOrigin.wearable, AlertChannel.cloud, AlertKind.fall, 12)).action,
        FusionAction.duplicate);
    expect(e.ingest(sig(AlertOrigin.wearable, AlertChannel.cloud, AlertKind.fall, 40)).shouldRing,
        isTrue);
  });

  test('unacknowledged: same seq repeats keep deduping (sliding window)', () {
    final e = AlertFusionEngine();
    expect(e.ingest(sig(AlertOrigin.wearable, AlertChannel.udp, AlertKind.fall, 0, seq: 5)).shouldRing,
        isTrue);
    for (final s in [0, 1, 2]) {
      expect(e.ingest(sig(AlertOrigin.wearable, AlertChannel.udp, AlertKind.fall, s, seq: 5)).action,
          FusionAction.duplicate);
    }
    expect(e.ingest(sig(AlertOrigin.wearable, AlertChannel.udp, AlertKind.fall, 50, seq: 5)).action,
        FusionAction.duplicate);
    expect(e.recent, hasLength(1));
  });

  test('clear() forgets history so a former duplicate rings', () {
    final e = AlertFusionEngine();
    e.ingest(sig(AlertOrigin.wearable, AlertChannel.udp, AlertKind.fall, 0, seq: 1));
    e.clear();
    expect(e.recent, isEmpty);
    expect(e.ingest(sig(AlertOrigin.wearable, AlertChannel.udp, AlertKind.fall, 1, seq: 1)).shouldRing,
        isTrue);
  });

  test('json round trip', () {
    final e = AlertFusionEngine();
    e.ingest(sig(AlertOrigin.wearable, AlertChannel.udp, AlertKind.fall, 0, metric: 2.5, seq: 9));
    final r = e.ingest(sig(AlertOrigin.camera, AlertChannel.ble, AlertKind.fall, 4, metric: 0.8));
    final back = AlertIncident.fromJson(r.incident.toJson())!;
    expect(back.id, r.incident.id);
    expect(back.multiSource, isTrue);
    expect(back.impactG, 2.5);
    expect(back.udpSeq[AlertOrigin.wearable], 9);
    expect(back.cameraConfidence, 0.8);
    expect(back.arrivals[AlertChannel.ble], const Duration(seconds: 4));
    final fr = FusionResult.fromJson(r.toJson())!;
    expect(fr.action, FusionAction.fused);
  });
}
