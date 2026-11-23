import 'package:donglgewi/main.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
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
    await tester.tap(find.textContaining('말 걸기'));
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
