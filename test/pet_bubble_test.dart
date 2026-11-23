import 'package:donglgewi/main.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  testWidgets('Duo delegates compact controls to UIKit and preserves a draft', (
    tester,
  ) async {
    const layout = MethodChannel('donglgewi/layout');
    final messenger = tester.binding.defaultBinaryMessenger;
    final calls = <MethodCall>[];
    messenger.setMockMethodCallHandler(layout, (call) async {
      calls.add(call);
      return call.method == 'roomToolbarVisible' ? true : null;
    });
    Future<void> native(String method, Object arguments) =>
        messenger.handlePlatformMessage(
          layout.name,
          const StandardMethodCodec().encodeMethodCall(
            MethodCall(method, arguments),
          ),
          (_) {},
        );
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(440, 640);
    tester.view.padding = const FakeViewPadding(right: 89, top: 18, bottom: 20);
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
    expect(find.text('돌보기'), findsNothing);
    expect(find.text('말 걸기'), findsNothing);
    expect(tester.getSize(stage).width, greaterThan(310));
    expect(tester.getTopRight(stage).dx, lessThanOrEqualTo(351));
    expect(calls.last.arguments, containsPair('bag', true));

    await native('roomToolbarAction', 'bag');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('아이템 얻기'), findsOneWidget);
    expect(calls.last.arguments, containsPair('bag', false));
    tester.state<NavigatorState>(find.byType(Navigator)).pop();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    await native('roomToolbarAction', 'talk');
    await tester.pump();
    final input = find.byType(EditableText);
    await tester.enterText(input, '우리 뭐 하고 놀까?');

    await native('roomToolbarVisibleChanged', false);
    tester.view.physicalSize = const Size(756, 822);
    tester.view.padding = const FakeViewPadding(left: 52, top: 18, bottom: 20);
    tester.view.viewInsets = const FakeViewPadding(bottom: 500);
    await tester.pump();
    expect(controls, findsOneWidget);
    expect(
      tester.getTopLeft(controls).dx,
      greaterThan(tester.getTopRight(stage).dx),
    );
    expect(
      tester.getCenter(input).dx,
      greaterThan(tester.getTopRight(stage).dx),
    );
    expect(tester.getBottomLeft(input).dy, lessThan(322));
    expect(tester.widget<EditableText>(input).controller.text, '우리 뭐 하고 놀까?');

    await native('roomToolbarVisibleChanged', true);
    tester.view.physicalSize = const Size(440, 640);
    tester.view.padding = const FakeViewPadding(right: 89, top: 18, bottom: 20);
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    await tester.pump();
    expect(controls, findsNothing);
    expect(tester.widget<EditableText>(input).controller.text, '우리 뭐 하고 놀까?');
    expect(tester.getBottomLeft(input).dy, lessThan(340));
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
    final lastReply = find.text('응, 나 여기 있어. 네가 오니까 좋아.');
    expect(tester.widget<Text>(lastReply).maxLines, 2);
    await tester.tap(lastReply);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('동글귀의 말'), findsOneWidget);
    final fullReply = tester.widget<SelectableText>(find.byType(SelectableText));
    expect(fullReply.data, '응, 나 여기 있어. 네가 오니까 좋아.');
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
  });
}
