import 'package:donglgewi/main.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Duo layout follows the native toolbar edge and keeps a draft', (
    tester,
  ) async {
    const layout = MethodChannel('donglgewi/layout');
    final messenger = tester.binding.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(layout, (_) async => 'left');
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(() {
      tester.view.reset();
      debugDefaultTargetPlatformOverride = null;
      messenger.setMockMethodCallHandler(layout, null);
    });

    await tester.runAsync(() async {
      await tester.pumpWidget(const PetApp());
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pump();
    final stage = find.byKey(const ValueKey('pet-stage'));
    final controls = find.byKey(const ValueKey('room-controls'));
    expect(controls, findsNothing);
    await tester.tap(find.text('말 걸기'));
    await tester.pump();
    final input = find.byType(EditableText);
    await tester.enterText(input, '우리 뭐 하고 놀까?');

    tester.view.physicalSize = const Size(756, 822);
    tester.view.padding = const FakeViewPadding(left: 52, top: 18, bottom: 20);
    await tester.pump();
    expect(controls, findsOneWidget);
    expect(tester.getTopLeft(controls).dx, greaterThanOrEqualTo(52));
    expect(tester.getCenter(controls).dx, lessThan(tester.getCenter(stage).dx));
    expect(tester.widget<EditableText>(input).controller.text, '우리 뭐 하고 놀까?');

    await messenger.handlePlatformMessage(
      layout.name,
      const StandardMethodCodec().encodeMethodCall(
        const MethodCall('toolbarSideChanged', 'right'),
      ),
      (_) {},
    );
    tester.view.padding = const FakeViewPadding(right: 52, top: 18, bottom: 20);
    await tester.pump();
    expect(
      tester.getCenter(controls).dx,
      greaterThan(tester.getCenter(stage).dx),
    );
    expect(tester.getTopRight(controls).dx, lessThanOrEqualTo(704));

    tester.view.physicalSize = const Size(390, 844);
    await tester.pump();
    expect(controls, findsNothing);
    expect(tester.widget<EditableText>(input).controller.text, '우리 뭐 하고 놀까?');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('replies stay in the room above an open keyboard', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.reset);

    await tester.runAsync(() async {
      await tester.pumpWidget(const PetApp());
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pump();
    await tester.tap(find.text('말 걸기'));
    await tester.pump();

    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    await tester.pump();
    final input = find.byType(EditableText);
    await tester.enterText(input, '원반으로 놀까?');
    await tester.tap(find.text('보내기'));
    await tester.pump();
    final reply = find.text('원반이 생기면 같이 놀자.');
    expect(reply, findsOneWidget);
    final pet = find.bySemanticsLabel('동글귀 톡 누르기');
    expect(pet, findsOneWidget);
    expect(tester.getCenter(reply).dy, lessThan(tester.getCenter(pet).dy));
    expect(tester.getBottomLeft(input).dy, lessThan(544));

    await tester.enterText(input, '안녕');
    await tester.tap(find.text('보내기'));
    await tester.pump();
    expect(reply, findsNothing);
    expect(find.text('응, 나 여기 있어. 네가 오니까 좋아.'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
  });
}
