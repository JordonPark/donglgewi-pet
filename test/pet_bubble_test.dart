import 'dart:async';

import 'package:donglgewi/main.dart';
import 'package:donglgewi/pet/pet_ending_scene.dart';
import 'package:donglgewi/pet/pet_voice.dart';
import 'package:donglgewi/pet/pet_game.dart';
import 'package:donglgewi/pet/pet_sprite.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart' show ImageSource;
import 'package:material_ui/material_ui.dart';

void main() {
  testWidgets('photo actions live in the bag and open the matching picker', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(440, 844);
    addTearDown(tester.view.reset);

    const channel = MethodChannel('plugins.flutter.io/image_picker');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final sources = <int>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'pickImage');
      sources.add(call.arguments['source'] as int);
      return null;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

    Future<void> tapLabel(String label) async {
      final target = find.text(label);
      await tester.ensureVisible(target);
      await tester.tap(target);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
    }

    await tester.runAsync(() async {
      await tester.pumpWidget(const PetApp());
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pump();
    expect(find.text('사진 찍기'), findsNothing);

    for (final label in ['사진 찍기', '앨범에서 선택']) {
      await tapLabel('가방');
      final photoEntry = find.text('아이템 얻기').hitTestable();
      expect(photoEntry, findsOneWidget);
      expect(find.text('사진에서 먹이와 물건을 찾아요.'), findsOneWidget);
      expect(
        tester.getTopLeft(photoEntry).dy,
        lessThan(tester.getTopLeft(find.text('기본 먹이 ×3')).dy),
      );
      await tapLabel('아이템 얻기');
      await tapLabel(label);
      expect(find.text('아이템 확인'), findsNothing);
    }
    expect(sources, [ImageSource.camera.index, ImageSource.gallery.index]);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('park buttons launch outdoor activities and show play gains', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(440, 844);
    addTearDown(tester.view.reset);

    Future<void> tapLabel(String label) async {
      final target = find.text(label);
      await tester.ensureVisible(target);
      await tester.tap(target);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
    }

    await tester.runAsync(() async {
      await tester.pumpWidget(const PetApp());
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pump();
    expect(find.text('원반 던지기'), findsNothing);
    await tapLabel('공원 산책');
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('먹이기'), findsNothing);
    expect(find.text('청소하기'), findsNothing);
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, '원반 던지기'))
          .onPressed,
      isNull,
    );
    await tapLabel('벤치에서 쉬기');
    expect(find.text('벤치 옆에서 잠깐 쉬자.'), findsOneWidget);
    await tapLabel('산책하기');
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.textContaining('솔방울이 숨어'), findsOneWidget);
    expect(find.textContaining('호기심 +1'), findsOneWidget);

    await tapLabel('가방');
    await tapLabel('아이템 얻기');
    await tapLabel('시연용 소풍 장면');
    await tapLabel('가방에 담기');
    expect(find.text('사진에서 원반을 찾았어요'), findsOneWidget);
    tester.state<NavigatorState>(find.byType(Navigator)).pop();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tapLabel('원반 던지기');
    await tapLabel('바로 던지기');
    expect(find.text('내가 받아올게!'), findsOneWidget);
    for (var step = 0; step < 5; step++) {
      await tester.pump(const Duration(milliseconds: 500));
    }
    expect(find.textContaining('잡았다!'), findsOneWidget);
    expect(find.textContaining('민첩 +1'), findsOneWidget);
    expect(find.textContaining('자신감 +1'), findsOneWidget);
    expect(find.text('잘했어!').hitTestable(), findsOneWidget);
    expect(find.text('조금 아쉬웠어').hitTestable(), findsOneWidget);

    await tapLabel('집으로');
    expect(find.text('산책하기'), findsNothing);
    expect(find.text('원반 던지기'), findsNothing);
    expect(find.text('한 번 더 던지기'), findsNothing);
    expect(find.text('먹이기'), findsWidgets);
    expect(find.text('청소하기'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  for (final searchRoute in [false, true]) {
    final ending = searchRoute ? '우리가 찾은 솔방울' : '마지막 원반';
    final keepsakeTitle = searchRoute ? '작은 솔방울' : '작은 원반';
    testWidgets(
      'three-day $ending route carries its keepsake into a new game',
      (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = const Size(440, 844);
        addTearDown(tester.view.reset);

        Future<void> frames([int count = 1]) async {
          await tester.pump();
          for (var i = 0; i < count; i++) {
            await tester.pump(const Duration(milliseconds: 500));
          }
        }

        Future<void> tap(Finder target) async {
          await tester.ensureVisible(target);
          await tester.tap(target);
          await frames();
        }

        Future<void> label(String text) => tap(find.text(text));

        await tester.runAsync(() async {
          await tester.pumpWidget(const PetApp());
          await Future<void>.delayed(const Duration(milliseconds: 100));
        });
        await frames();
        await label('설정');
        await label('시연 새로 시작 · 첫날 18시');
        await label('새로 시작');
        if (!searchRoute) {
          await label('가방');
          await label('아이템 얻기');
          await label('시연용 소풍 장면');
          await label('가방에 담기');
          tester.state<NavigatorState>(find.byType(Navigator)).pop();
          await frames();
        }
        await label('먹이기');
        await label(searchRoute ? '기본 먹이 1개' : '사과 1개');
        await frames(3);

        await label('공원 산책');
        await frames(3);
        tester.view.physicalSize = const Size(440, 640);
        tester.view.padding = const FakeViewPadding(
          right: 89,
          top: 18,
          bottom: 20,
        );
        await frames();
        final waitPose = find.byKey(const ValueKey('pet-wait-pose'));
        if (searchRoute) {
          await label('산책하기');
          await frames(3);
          expect(find.text('찾아봐').hitTestable(), findsOneWidget);
          expect(
            find.byKey(const ValueKey('park-shortcut-stone')),
            findsNothing,
          );
          await label('찾아봐');
          final target = PetSearchSpot.values.singleWhere(
            (spot) => find.textContaining(spot.hint).evaluate().isNotEmpty,
          );
          final wrong = PetSearchSpot.values.firstWhere(
            (spot) => spot != target,
          );
          await tap(find.widgetWithText(ActionChip, wrong.label).hitTestable());
          expect(find.textContaining('거긴 아닌 것 같아'), findsOneWidget);
          await tap(
            find.widgetWithText(ActionChip, target.label).hitTestable(),
          );
          await frames(3);
          expect(find.textContaining('다음에도 내가 먼저 살펴볼게'), findsOneWidget);
        } else {
          await label('원반 던지기');
          expect(find.text('기다려').hitTestable(), findsOneWidget);
          await label('기다려');
          expect(find.text('던져줄게').hitTestable(), findsOneWidget);
          expect(tester.widget<AnimatedScale>(waitPose).scale, .91);
          await label('던져줄게');
          await frames(6);
          expect(find.textContaining('기다렸다가 잡았어'), findsOneWidget);
        }
        tester.view.resetPadding();
        tester.view.physicalSize = const Size(440, 844);
        await frames();
        if (searchRoute) {
          await label('집으로');
          await label('가방');
          await label('방에 두기');
          await tap(find.widgetWithText(ActionChip, '창가').hitTestable());
          await frames(2);
          final window = find.byKey(const ValueKey('room-pinecone-window'));
          expect(window, findsOneWidget);
          final windowX = tester.getCenter(window).dx;
          expect(find.text('별 보러 갈까?'), findsNothing);
          await label('공원 산책');
          await frames(3);
          await label('집으로');
          expect(find.text('별 보러 갈까?'), findsOneWidget);
          await label('같이 보자');
          expect(find.text('별 앨범에 담기'), findsOneWidget);
          tester.state<NavigatorState>(find.byType(Navigator)).pop();
          await frames();
          await label('다음에 보자');
          await label('가방');
          await label('자리 바꾸기');
          await tap(find.widgetWithText(ActionChip, '러그 옆').hitTestable());
          await frames(2);
          final rug = find.byKey(const ValueKey('room-pinecone-rug'));
          expect(tester.getCenter(rug).dx, lessThan(windowX));
          expect(find.text('러그에서 같이 앉을래?'), findsNothing);
          await label('공원 산책');
          await frames(3);
          await label('집으로');
          expect(find.text('러그에서 같이 앉을래?'), findsOneWidget);
          await label('같이 앉자');
          expect(find.text('응, 러그가 포근해.'), findsOneWidget);
          await label('공원 산책');
          await frames(3);
          await label('집으로');
          expect(find.text('러그에서 같이 앉을래?'), findsNothing);
          await label('공원 산책');
          await frames(3);
        }

        await label('설정');
        await label('24시간 뒤 재방문');
        final care = find.byKey(const ValueKey('care-warning'));
        expect(
          find.descendant(
            of: care,
            matching: find.textContaining(RegExp(r'굶주림 · .* 남음')),
          ),
          findsOneWidget,
        );
        await tap(find.descendant(of: care, matching: find.text('집으로 이동')));
        expect(
          find.descendant(of: care, matching: find.text('먹이 주기')),
          findsOneWidget,
        );
        await label('청소하기');
        await frames(7);
        await label('먹이기');
        final twoMeals = find.ancestor(
          of: find.text('기본 먹이 2개'),
          matching: find.byType(ListTile),
        );
        expect(
          find.descendant(
            of: twoMeals,
            matching: find.textContaining('청소 전 예상 배변 2/3'),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: twoMeals,
            matching: find.textContaining(RegExp(r'돌보지 않으면 .* · 굶주림 위험')),
          ),
          findsOneWidget,
        );
        await label('기본 먹이 2개');
        await frames(3);
        expect(
          tester
              .widgetList<PetSprite>(find.byType(PetSprite))
              .any((sprite) => sprite.stage == PetStage.young),
          isTrue,
        );
        if (!searchRoute) {
          expect(
            find.textContaining('이제 괜찮아. 어제 ‘공원 소풍’에서 가져온 원반'),
            findsOneWidget,
          );
        }
        await label('공원 산책');
        await frames(3);
        if (searchRoute) {
          expect(find.textContaining('그때 배운 대로 찾아볼게'), findsOneWidget);
          expect(find.byType(ActionChip), findsNWidgets(3));
          final spot = PetSearchSpot.values.singleWhere(
            (entry) => find.textContaining(entry.hint).evaluate().isNotEmpty,
          );
          await tap(find.widgetWithText(ActionChip, spot.label).hitTestable());
          final stone = find.byKey(const ValueKey('park-shortcut-stone'));
          await frames(1);
          expect(tester.widget<IconButton>(stone).onPressed, isNull);
          await frames(3);
          final artwork = tester.getRect(
            find.byKey(const ValueKey('room-artwork')),
          );
          final stoneCenter = tester.getCenter(stone);
          expect(
            stoneCenter.dx,
            closeTo(artwork.left + artwork.width * .322, 1),
          );
          expect(tester.getCenter(waitPose).dx, lessThan(stoneCenter.dx));
          expect(stone.hitTestable(), findsOneWidget);
          await tap(stone);
          await frames(7);
          expect(
            find.widgetWithText(ActionChip, '나무 뒤 풀밭').hitTestable(),
            findsOneWidget,
          );
          await tap(find.widgetWithText(ActionChip, '나무 뒤 풀밭'));
          await frames(3);
          expect(find.text('솔방울 발견'), findsOneWidget);
          expect(find.byKey(const ValueKey('park-disc-routes')), findsNothing);

          await label('설정');
          await label('36시간 뒤 · 원반 착지점');
          await label('집으로');
          await label('청소하기');
          await frames(7);
          await label('먹이기');
          await label('기본 먹이 1개');
          await frames(3);
          await label('가방');
          await label('아이템 얻기');
          await label('시연용 소풍 장면');
          await label('가방에 담기');
          final discDetail = RegExp(r'^내구도 (\d)/(\d)$');
          final newDisc = tester
              .widget<Text>(find.textContaining(discDetail))
              .data!;
          final durability = int.parse(discDetail.firstMatch(newDisc)![1]!);
          tester.state<NavigatorState>(find.byType(Navigator)).pop();
          await frames();
          await label('공원 산책');
          await frames(3);
          tester.view.physicalSize = const Size(440, 640);
          tester.view.padding = const FakeViewPadding(
            right: 89,
            top: 18,
            bottom: 20,
          );
          await frames();
          await label('원반 던지기');
          expect(
            find.byKey(const ValueKey('park-disc-routes')),
            findsOneWidget,
          );
          expect(
            find.widgetWithText(ActionChip, '가까운 잔디').hitTestable(),
            findsOneWidget,
          );
          expect(
            find.widgetWithText(ActionChip, '벤치 너머').hitTestable(),
            findsOneWidget,
          );
          String energy() => tester
              .widget<Text>(find.textContaining(RegExp(r'^\d+\.\d%$')))
              .data!;
          final energyBefore = energy();
          final farLane = find.widgetWithText(ActionChip, '벤치 너머');
          final readyThrow = find.widgetWithText(ActionChip, '지금 던지기');
          await tap(farLane);
          final preparing = find.widgetWithText(ActionChip, '준비 중…');
          expect(tester.widget<ActionChip>(preparing).onPressed, isNull);
          expect(readyThrow, findsNothing);
          expect(tester.widget<AnimatedScale>(waitPose).scale, .91);
          expect(energy(), energyBefore);
          await tester.tap(
            find.byKey(const ValueKey('pet-speech-close')).hitTestable(),
          );
          await frames(2);
          expect(readyThrow, findsNothing);
          expect(energy(), energyBefore);
          await label('가방');
          expect(
            find.textContaining('내구도 $durability/$durability'),
            findsOneWidget,
          );
          tester.state<NavigatorState>(find.byType(Navigator)).pop();
          await frames();
          await label('원반 던지기');
          await tap(farLane);
          await tester.pump(const Duration(milliseconds: 201));
          expect(readyThrow.hitTestable(), findsOneWidget);
          expect(energy(), energyBefore);
          await tap(readyThrow);
          expect(find.byKey(const ValueKey('park-disc-routes')), findsNothing);
          var peak = 0.0;
          final hop = find.byKey(const ValueKey('pet-hop'));
          for (var frame = 0; frame < 30; frame++) {
            await tester.pump(const Duration(milliseconds: 100));
            final lift = -tester.widget<AnimatedSlide>(hop).offset.dy;
            if (lift > peak) peak = lift;
          }
          expect(peak, greaterThan(.4));
          expect(find.textContaining('잡았다!'), findsOneWidget);
          expect(
            find.textContaining(durability == 1 ? '원반 소진' : '내구도 −1'),
            findsOneWidget,
          );
          final change =
              double.parse(energyBefore.replaceAll('%', '')) -
              double.parse(energy().replaceAll('%', ''));
          expect(change, closeTo(100 * PetPlay.disc.cost / 576, .2));
          await label('가방');
          if (durability == 1) {
            expect(find.text('원반 ×0'), findsOneWidget);
          } else {
            expect(
              find.textContaining('내구도 ${durability - 1}/$durability'),
              findsOneWidget,
            );
          }
          tester.state<NavigatorState>(find.byType(Navigator)).pop();
          await frames();
          tester.view.resetPadding();
          tester.view.physicalSize = const Size(440, 844);
          await frames();
        } else {
          expect(tester.widget<AnimatedScale>(waitPose).scale, .91);
          expect(find.textContaining('그때 배운 대로 기다릴게'), findsOneWidget);
        }

        await label('설정');
        await label('48시간 뒤 · 셋째 날');
        await label('집으로');
        await label('청소하기');
        await frames(7);
        await label('먹이기');
        await label('기본 먹이 1개');
        await frames(3);
        await label('성장 엔딩 보기');
        await label(ending);
        expect(find.textContaining('가르쳤고,'), findsOneWidget);
        expect(find.text(searchRoute ? '찾아봐' : '기다려'), findsOneWidget);
        await frames(6);
        expect(find.text('다음 펫에게 남길 기념품 · $keepsakeTitle'), findsOneWidget);
        if (searchRoute) {
          expect(find.textContaining('처음 찾았던 자리'), findsOneWidget);
        } else {
          expect(find.text('‘공원 소풍’에서 가져온 원반'), findsOneWidget);
        }
        await label('새 펫 키우기');
        await label('잎귀');
        await label('초기화하고 시작');
        final keepsake = find.byKey(const ValueKey('pet-keepsake'));
        expect(keepsake, findsOneWidget);
        await tap(keepsake);
        await frames(3);
        expect(find.textContaining('$keepsakeTitle 옆'), findsOneWidget);
        if (searchRoute) {
          await label('러그 옆에서 찾아보기');
          await frames(4);
          expect(find.textContaining('탐색 연습'), findsOneWidget);
          expect(find.text('집으로'), findsNothing);
        } else {
          await label('공원으로 가져가기');
          await frames(4);
          expect(find.text('집으로'), findsOneWidget);
          expect(find.text('기다려'), findsOneWidget);
        }
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }

  testWidgets('care can interrupt a pending voice reply', (tester) async {
    final voice = _PendingVoice();
    await tester.runAsync(() async {
      await tester.pumpWidget(PetApp(voice: voice));
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pump();
    Future<void> press(String label) async {
      final target = find.text(label);
      await tester.ensureVisible(target);
      await tester.tap(target);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 420));
    }

    await press('말 걸기');
    await press('오늘 기분 어때?');
    expect(voice.requests, 1);
    await press('먹이기');
    expect(voice.cancelled, isTrue);
    await press('기본 먹이 1개');
    voice.answer.complete((text: '늦게 도착한 대사', tokens: 22));
    await tester.pump();
    expect(find.text('늦게 도착한 대사'), findsNothing);
    expect(find.bySemanticsLabel('체력 100.0%'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('a hunger farewell opens the album', (tester) async {
    await tester.runAsync(() async {
      await tester.pumpWidget(const PetApp());
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pump();
    Future<void> press(String label) async {
      final target = find.text(label);
      await tester.ensureVisible(target);
      await tester.tap(target);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 450));
    }

    await press('설정');
    await press('시연 새로 시작 · 첫날 18시');
    await press('새로 시작');
    await press('설정');
    await press('48시간 뒤 · 셋째 날');
    await press('마지막 인사 보기');
    final farewell = tester.widget<PetFarewellScene>(
      find.byType(PetFarewellScene),
    );
    expect(farewell.hunger, isTrue);
    expect(find.textContaining('굶주림으로'), findsWidgets);
    await press('남은 추억 보기');
    expect(find.text('앨범·도감'), findsWidgets);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('the idle pet blinks and reset selects a different character', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(440, 844);
    addTearDown(tester.view.reset);

    Future<void> tapLabel(String label) async {
      final target = find.text(label);
      await tester.ensureVisible(target);
      await tester.tap(target);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 450));
    }

    await tester.runAsync(() async {
      await tester.pumpWidget(const PetApp());
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pump();
    final sprite = find.byType(PetSprite);
    expect(tester.widget<PetSprite>(sprite).blink, isFalse);
    await tester.pump(const Duration(seconds: 3));
    expect(tester.widget<PetSprite>(sprite).blink, isTrue);
    await tester.pump(const Duration(milliseconds: 200));
    expect(tester.widget<PetSprite>(sprite).blink, isFalse);
    final margin = tester.widget<AnimatedPadding>(
      find.byKey(const ValueKey('room-safe-margin')),
    );
    expect(margin.padding, const EdgeInsets.only(bottom: 20));

    await tapLabel('설정');
    await tapLabel('펫 초기화');
    await tapLabel('잎귀');
    await tapLabel('취소');
    expect(tester.widget<PetSprite>(sprite).kind, PetKind.dongle);
    await tapLabel('설정');
    await tapLabel('펫 초기화');
    await tapLabel('별꼬리');
    await tapLabel('초기화하고 시작');
    expect(tester.widget<PetSprite>(sprite).kind, PetKind.star);
    expect(find.bySemanticsLabel('체력 100.0%'), findsOneWidget);
    await tapLabel('앨범·도감');
    expect(find.text('키워봤어요'), findsOneWidget);
    expect(find.text('지금 키우는 중'), findsOneWidget);
    tester.state<NavigatorState>(find.byType(Navigator)).pop();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 450));
    await tapLabel('펫 정보');
    expect(find.text('별꼬리 펫 정보'), findsOneWidget);
    expect(find.text('다음 성장 · 꼬마'), findsOneWidget);
    expect(find.textContaining('성격 · '), findsOneWidget);
    expect(find.text('능력치'), findsOneWidget);
    expect(find.text('호기심'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('the pet shows hearts and asks for space after repeated taps', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(440, 844);
    addTearDown(tester.view.reset);
    await tester.runAsync(() async {
      await tester.pumpWidget(const PetApp());
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pump();
    final pet = find.byKey(const ValueKey('pet-touch-target'));
    final hearts = find.byKey(const ValueKey('pet-pat-hearts'));
    await tester.tap(pet);
    await tester.pump(const Duration(milliseconds: 16));
    expect(find.text('헤헤, 좋아!'), findsOneWidget);
    expect(hearts, findsOneWidget);
    for (var tap = 0; tap < 3; tap++) {
      await tester.tap(pet);
      await tester.pump(const Duration(milliseconds: 80));
    }
    expect(hearts, findsNothing);
    expect(find.text('너무 많이 만지면 싫어. 잠깐 쉬게 해줘.'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('tapping waste clears the room after three seconds', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(440, 844);
    addTearDown(tester.view.reset);

    Future<void> tapLabel(String label) async {
      final target = find.text(label);
      await tester.ensureVisible(target);
      await tester.tap(target);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
    }

    await tester.runAsync(() async {
      await tester.pumpWidget(const PetApp());
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pump();
    await tapLabel('설정');
    await tapLabel('시연 새로 시작 · 첫날 18시');
    await tapLabel('새로 시작');
    await tapLabel('먹이기');
    await tapLabel('기본 먹이 1개');
    for (final time in [500, 250, 300]) {
      await tester.pump(Duration(milliseconds: time));
    }
    await tapLabel('설정');
    await tapLabel('15시간 뒤 재방문');

    final waste = find.byKey(const ValueKey('room-waste-0'));
    final progress = find.text('청소 중');
    expect(waste, findsOneWidget);
    await tester.tap(waste);
    await tester.pump();
    expect(progress, findsOneWidget);
    await tester.pump(const Duration(seconds: 2));
    await tester.tap(waste);
    tester.view.physicalSize = const Size(756, 822);
    await tester.pump(const Duration(milliseconds: 900));
    expect(waste, findsOneWidget);
    expect(progress, findsOneWidget);

    await tester.pump(const Duration(milliseconds: 100));
    expect(waste, findsNothing);
    expect(progress, findsNothing);
    expect(find.bySemanticsLabel('배변 0/3'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('Duo keeps choices in the scene and UIKit actions available', (
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
    expect(find.text('먹이기'), findsOneWidget);
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
    final choices = find.byKey(const ValueKey('pet-choice-bubble'));
    expect(choices, findsOneWidget);
    expect(find.byType(EditableText), findsNothing);
    expect(calls.last.arguments, containsPair('bag', true));

    await native('roomToolbarVisibleChanged', false);
    tester.view.physicalSize = const Size(756, 822);
    tester.view.padding = const FakeViewPadding(left: 52, top: 18, bottom: 20);
    await tester.pump();
    expect(controls, findsOneWidget);
    expect(
      tester.getTopLeft(controls).dx,
      greaterThan(tester.getTopRight(stage).dx),
    );
    expect(
      tester.getTopRight(choices).dx,
      lessThan(tester.getTopLeft(controls).dx),
    );
    expect(
      tester.getTopLeft(find.text('체력')).dy,
      lessThan(tester.getTopLeft(find.text('가방')).dy),
    );
    expect(find.text('오늘 기분 어때?').hitTestable(), findsOneWidget);

    await native('roomToolbarVisibleChanged', true);
    tester.view.physicalSize = const Size(440, 640);
    tester.view.padding = const FakeViewPadding(right: 89, top: 18, bottom: 20);
    await tester.pump();
    expect(controls, findsNothing);
    expect(find.text('오늘 기분 어때?').hitTestable(), findsOneWidget);
    expect(find.byType(EditableText), findsNothing);
    expect(find.text('먹이기'), findsOneWidget);
    expect(calls.last.arguments, containsPair('bag', true));
    await tester.pump(const Duration(milliseconds: 220));
    final beforeClose = tester.getTopLeft(choices).dy;
    await tester.tap(
      find.descendant(
        of: choices,
        matching: find.byKey(const ValueKey('pet-speech-close')),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 90));
    expect(choices, findsOneWidget);
    expect(tester.getTopLeft(choices).dy, lessThan(beforeClose));
    expect(find.text('오늘 기분 어때?').hitTestable(), findsNothing);
    await native('roomToolbarAction', 'bag');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('아이템 얻기'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'large text keeps every choice reachable on a short portrait and after rotation',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(320, 568);
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(() {
        tester.view.reset();
        tester.platformDispatcher.clearTextScaleFactorTestValue();
      });
      await tester.runAsync(() async {
        await tester.pumpWidget(const PetApp());
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pump();

      final artwork = find.byKey(const ValueKey('room-artwork'));
      final stage = find.byKey(const ValueKey('pet-stage'));
      final pet = find.byKey(const ValueKey('pet-touch-target'));
      expect(
        tester.getSize(artwork).width,
        greaterThan(tester.getSize(stage).width * 1.15),
      );
      expect(tester.getSize(pet).height, greaterThanOrEqualTo(48));

      final talk = find.text('말 걸기');
      await tester.ensureVisible(talk);
      await tester.tap(talk);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));
      await tester.pump(const Duration(milliseconds: 250));
      final choices = find.byKey(const ValueKey('pet-choice-bubble'));
      final buttons = find.descendant(
        of: choices,
        matching: find.byType(TextButton),
      );
      expect(buttons.hitTestable(), findsNWidgets(3));
      expect(
        find.descendant(of: choices, matching: find.byType(Scrollable)),
        findsNothing,
      );
      expect(find.byTooltip('말풍선 닫기').hitTestable(), findsOneWidget);
      for (final element in buttons.evaluate()) {
        expect(
          tester
              .getSize(find.byElementPredicate((item) => item == element))
              .height,
          greaterThanOrEqualTo(48),
        );
      }

      tester.view.physicalSize = const Size(844, 390);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));
      final controls = find.byKey(const ValueKey('room-controls'));
      expect(
        tester.getTopRight(choices).dx,
        lessThan(tester.getTopLeft(controls).dx),
      );
      expect(buttons.hitTestable(), findsNWidgets(3));
      await tester.tap(find.text('한마디 해줄게'));
      await tester.pump();
      expect(find.text('조금 아쉬웠어').hitTestable(), findsOneWidget);
      expect(find.byType(EditableText), findsNothing);

      tester.view.physicalSize = const Size(320, 568);
      await tester.pump();
      Future<void> press(String label) async {
        final target = find.text(label);
        await tester.ensureVisible(target);
        await tester.tap(target);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 420));
      }

      await press('설정');
      await press('시연 새로 시작 · 첫날 18시');
      await press('새로 시작');
      await press('설정');
      await press('24시간 뒤 재방문');
      final warning = find.byKey(const ValueKey('care-warning'));
      expect(warning.hitTestable(), findsOneWidget);
      expect(
        find.textContaining(RegExp(r'굶주림 · .* 남음')).hitTestable(),
        findsOneWidget,
      );
      await press('먹이 주기');
      final forecast = find.textContaining(RegExp(r'돌보지 않으면 .*위생 악화 위험'));
      await tester.ensureVisible(forecast);
      await tester.pump();
      expect(forecast.hitTestable(), findsOneWidget);
      expect(tester.widget<Text>(forecast).maxLines, isNull);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'selected replies remain in the scene and vary without a keyboard',
    (tester) async {
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
      final choices = find.byKey(const ValueKey('pet-choice-bubble'));
      expect(
        find.descendant(of: choices, matching: find.byType(TextButton)),
        findsNWidgets(3),
      );
      expect(find.byType(EditableText), findsNothing);

      await tester.tap(find.text('오늘 기분 어때?'));
      await tester.pump();
      await tester.pump();
      final first = find.text('네가 오니까 기분이 좋아.');
      expect(first, findsOneWidget);
      await tester.tap(find.text('오늘 기분 어때?'));
      await tester.pump();
      await tester.pump();
      expect(first, findsNothing);
      final second = find.textContaining('오늘 기분은');
      expect(second, findsOneWidget);
      await tester.tap(find.text('한마디 해줄게'));
      await tester.pump();
      expect(find.text('잘했어!').hitTestable(), findsOneWidget);
      final concern = find.text('조금 아쉬웠어').hitTestable();
      expect(concern, findsOneWidget);
      await tester.tap(concern);
      await tester.pump();
      await tester.tap(concern);
      await tester.pump();
      expect(find.textContaining('또 들으니까 마음이'), findsOneWidget);
      expect(find.textContaining('체력 −1.8%'), findsOneWidget);
      expect(find.textContaining(RegExp(r'(기분|자신감) −[12]')), findsOneWidget);
      expect(find.byType(EditableText), findsNothing);
      await tester.tap(find.textContaining('또 들으니까 마음이'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('동글귀의 말'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}

class _PendingVoice implements PetVoice {
  final answer = Completer<({String text, int tokens})?>();
  int requests = 0;
  bool cancelled = false;

  @override
  Future<({String text, int tokens})?> reply(
    String state,
    String message,
    int limit,
  ) {
    requests++;
    return answer.future;
  }

  @override
  void cancel() => cancelled = true;

  @override
  Future<void> dispose() async {}
}
