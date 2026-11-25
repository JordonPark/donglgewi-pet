import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:donglgewi/pet/pet_game.dart';

void main() {
  final firstEvening = DateTime(2026, 11, 23, 18);

  PetGame firstVisit() {
    final game = PetGame(firstEvening);
    game.addFinds('공원 소풍', apple: true, frisbee: false);
    game.discs.add(const PetDisc(3, 3));
    expect(game.feed(apple: true), isTrue);
    game.inPark = true;
    expect(game.play(PetPlay.disc), isNotNull);
    return game;
  }

  test(
    'first visit can feed and play immediately and retains a memory at 15h',
    () {
      final game = PetGame.decode(firstVisit().encode());
      expect(
        (game.apples, game.fullness, game.affection, game.disc),
        (0, 3, 2, true),
      );
      game.advance(firstEvening.add(hour * 15));
      expect((game.fullness, game.waste, game.healthy), (1, 1, true));
      expect(game.nextMemory?.title, '공원 소풍');
    },
  );

  test(
    '24h return can recover from hunger and still has yesterday’s memory',
    () {
      final game = firstVisit();
      game.advance(firstEvening.add(hour * 24));
      expect((game.fullness, game.waste, game.healthy), (0, 1, false));
      expect(game.alive, isTrue);
      expect(game.feed(apple: false), isFalse);
      game.inPark = false;
      expect(game.feed(apple: false), isTrue);
      expect(game.healthy, isTrue);
      expect(game.nextMemory?.title, '공원 소풍');
      expect(PetGame.decode(game.encode()).nextMemory?.title, '공원 소풍');
    },
  );

  test(
    'three queued meals tighten hygiene deadline and cleaning cancels it',
    () {
      final game = PetGame(firstEvening);
      expect(game.feed(apple: false), isTrue);
      final secondEvening = firstEvening.add(hour * 24);
      game.advance(secondEvening);
      game.inPark = false;
      expect(game.clean(), isTrue);
      for (var index = 0; index < 3; index++) {
        expect(game.feed(apple: false), isTrue);
      }
      expect(game.digestion, [
        for (final hours in [2, 5, 8]) secondEvening.add(hour * hours),
      ]);
      final forgotten = PetGame.decode(game.encode());
      forgotten.advance(secondEvening.add(hour * 16));
      expect(forgotten.death, '위생 악화');
      game.advance(secondEvening.add(hour * 15));
      expect(game.waste, 3);
      expect(game.clean(), isTrue);
      game.advance(secondEvening.add(hour * 16));
      expect(game.alive, isTrue);
    },
  );

  test('daily care survives three days and has a six-hour delay margin', () {
    final game = firstVisit();
    void careAt(int hours) {
      game.advance(firstEvening.add(hour * hours));
      expect(game.alive, isTrue);
      game.inPark = false;
      expect(game.clean(), isTrue);
      for (var meal = 0; meal < 2; meal++) {
        expect(game.feed(apple: false), isTrue);
      }
    }

    careAt(24);
    final daily = PetGame.decode(game.encode());
    daily.advance(firstEvening.add(hour * 48));
    expect(daily.alive, isTrue);
    final late = PetGame.decode(game.encode());
    late.advance(firstEvening.add(hour * 54 - const Duration(minutes: 1)));
    expect(late.alive, isTrue);
    expect(late.hungerDeadline, firstEvening.add(hour * 54));

    final skipped = PetGame.decode(game.encode());
    skipped.advance(firstEvening.add(hour * 72));
    expect((skipped.at, skipped.death), (firstEvening.add(hour * 54), '굶주림'));

    careAt(53);
    careAt(77);
    expect((game.alive, game.level), (true, 5));
  });

  test(
    'missing one cleaning can fill the third slot before the next visit',
    () {
      final game = firstVisit()..inPark = false;
      game.advance(firstEvening.add(hour * 24));
      expect(game.waste, 1);
      expect(game.feed(apple: false), isTrue);
      expect(game.feed(apple: false), isTrue);
      final recovered = PetGame.decode(game.encode());
      recovered.advance(firstEvening.add(hour * 40));
      expect((recovered.alive, recovered.waste), (true, 3));
      expect(recovered.clean(), isTrue);
      expect(recovered.feed(apple: false), isTrue);
      recovered.advance(firstEvening.add(hour * 41));
      expect(recovered.healthy, isTrue);

      game.advance(firstEvening.add(hour * 48));
      expect((game.at, game.death), (firstEvening.add(hour * 41), '위생 악화'));
    },
  );

  test('affection is once per activity and growth and energy round-trip', () {
    final game = firstVisit();
    game.mark(PetActivity.bond);
    game.mark(PetActivity.bond);
    expect((game.affection, game.level, game.maxEnergy), (3, 2, 448));
    game.spend(18);
    expect(game.energy, 398);
    game.advance(firstEvening.add(const Duration(minutes: 30)));
    expect(game.energy, 448);
    final steady = PetGame.decode(game.encode());
    expect((steady.energy, steady.affection, steady.level), (448, 3, 2));
  });

  test(
    'play spends shared energy and awards the right persistent abilities',
    () {
      final game = PetGame(firstEvening, kind: PetKind.leaf)
        ..level = 2
        ..discs.add(const PetDisc(3, 3));
      expect(game.play(PetPlay.walk), isNull);
      expect(game.play(PetPlay.disc), isNull);
      expect((game.energy, game.discs.single.remaining), (384, 3));
      game.inPark = true;
      final disc = game.play(PetPlay.disc)!;
      expect(disc.gains, {'민첩': 1, '자신감': 1, '기분': 1});
      expect(game.energy, 352);

      final stroll = game.play(PetPlay.walk)!;
      expect(stroll.gains, {'호기심': 1, '기분': 1});
      expect(game.energy, 336);
      expect(game.affection, 1);
      game.advance(firstEvening.add(recoveryInterval));
      expect(game.energy, 400);
      final restored = PetGame.decode(game.encode());
      expect(
        (
          restored.kind,
          restored.agility,
          restored.confidence,
          restored.curiosity,
          restored.mood,
        ),
        (PetKind.leaf, 1, 6, 1, 7),
      );

      restored.energy = 15;
      expect(restored.play(PetPlay.walk), isNull);
      expect(restored.energy, 15);
      expect(restored.curiosity, 1);

      restored.energy = 100;
      restored.curiosity = 10;
      restored.mood = 10;
      expect(restored.play(PetPlay.walk)!.gains, isEmpty);
      expect(restored.energy, 84);
    },
  );

  test('repeated play spends stamina but training renews with the date', () {
    final game = PetGame(firstEvening)
      ..level = 4
      ..inPark = true
      ..discs.addAll(List.filled(2, const PetDisc(5, 5)));
    expect(game.play(PetPlay.disc)!.repeated, isFalse);
    final restored = PetGame.decode(game.encode());
    for (var repetition = 0; repetition < 4; repetition++) {
      expect(
        restored.play(PetPlay.disc, lane: PetDiscLane.far)!.gains,
        isEmpty,
      );
    }
    expect((restored.agility, restored.confidence), (1, 6));
    expect((restored.energy, restored.discs.length), (224, 1));
    expect(restored.play(PetPlay.walk)!.gains['호기심'], 1);
    expect(restored.play(PetPlay.walk)!.repeated, isTrue);
    expect(
      restored.play(PetPlay.walk, route: PetParkRoute.shortcut)!.gains['호기심'],
      1,
    );
    restored.advance(firstEvening.add(hour * 7));
    expect(restored.play(PetPlay.disc)!.gains['자신감'], 1);
  });

  test('conversation spends on replies and personality steers the reward', () {
    final active = PetGame(firstEvening, personality: const PetPersonality(2));
    final quiet = PetGame(firstEvening, personality: const PetPersonality(0));
    for (final topic in ['disc', 'room', 'memory', 'park']) {
      final energetic = active.replyTo(
        PetTalk.encouragement,
        topic,
        random: const _Roll(69),
      )!;
      final relaxed = quiet.replyTo(
        PetTalk.encouragement,
        topic,
        random: const _Roll(69),
      )!;
      expect(energetic.changes, {'자신감': 1});
      expect(relaxed.changes, {'기분': 1});
    }
    expect((active.confidence, active.mood), (9, 5));
    expect((quiet.confidence, quiet.mood), (5, 9));
    expect(active.energy, active.maxEnergy - 4 * PetGame.shortReplyCost);
    final beforeModelReply = active.energy;
    expect(
      active.replyTo(PetTalk.question, 'memory', shownTokens: 18)!.changes,
      isEmpty,
    );
    expect(active.energy, beforeModelReply - 18);
    expect(
      active
          .replyTo(PetTalk.encouragement, 'walk', random: const _Roll(70))!
          .changes,
      isEmpty,
    );
    expect(
      quiet.replyTo(PetTalk.concern, 'room', random: const _Roll(69))!.changes,
      {'기분': -1},
    );
    expect(
      quiet.replyTo(PetTalk.concern, 'room', random: const _Roll(69))!.changes,
      {'기분': -2},
    );
    expect(
      quiet.replyTo(PetTalk.concern, 'room', random: const _Roll(70))!.changes,
      {'기분': -1},
    );
    quiet.mood = 1;
    expect(
      quiet.replyTo(PetTalk.concern, 'room', random: const _Roll(0))!.changes,
      {'기분': -1},
    );
    expect(quiet.mood, 0);
    final newPet = PetGame(firstEvening);
    newPet.replyTo(PetTalk.concern, 'room', random: const _Roll(0));
    expect(newPet.affection, 0);
    expect(newPet.energy, 384 - PetGame.shortReplyCost);

    active.energy = 7;
    final tired = active.encode();
    expect(
      active.replyTo(PetTalk.encouragement, 'search', random: const _Roll(0)),
      isNull,
    );
    expect(active.encode(), tired);
  });

  test('repetition survives reload and boredom happens once on that date', () {
    for (final (bits, threshold) in [(4, 3), (0, 4)]) {
      var game = PetGame(firstEvening, personality: PetPersonality(bits));
      expect(
        game
            .replyTo(PetTalk.encouragement, 'disc', random: const _Roll(0))!
            .changes,
        {'기분': 1},
      );
      for (var i = 2; i < threshold; i++) {
        expect(game.replyTo(PetTalk.encouragement, 'disc')!.changes, isEmpty);
      }
      game = PetGame.decode(game.encode());
      expect(game.willBeBored(PetTalk.encouragement, 'disc'), isTrue);
      expect(game.replyTo(PetTalk.encouragement, 'disc')!.changes, {'기분': -1});
      game = PetGame.decode(game.encode());
      for (var i = 0; i < threshold; i++) {
        expect(game.replyTo(PetTalk.question, 'room')!.changes, isEmpty);
      }
      game.advance(firstEvening.add(hour * 7));
      expect(
        game
            .replyTo(PetTalk.encouragement, 'disc', random: const _Roll(0))!
            .changes,
        {'기분': 1},
      );
    }
  });

  test(
    'the three-day lesson survives a daily visit and leaves one keepsake',
    () {
      var game = PetGame(firstEvening)..discs.add(const PetDisc(2, 2));
      expect(game.feed(apple: false), isTrue);
      expect(game.play(PetPlay.disc, teachWait: true), isNull);
      expect(game.waitTaughtAt, isNull);
      game.inPark = true;
      expect(game.play(PetPlay.disc, teachWait: true), isNotNull);
      expect(game.affection, 3);
      expect(game.waitTaughtAt, firstEvening);
      expect(game.recallWait(), isFalse);
      expect(game.availableEndings, isEmpty);

      game = PetGame.decode(game.encode());
      final secondVisit = firstEvening.add(hour * 24);
      game.advance(secondVisit);
      expect(game.alive, isTrue);
      expect(game.recallWait(), isFalse);
      game.inPark = false;
      expect(game.clean(), isTrue);
      expect(game.feed(apple: false), isTrue);
      expect(game.feed(apple: false), isTrue);
      expect(game.level, 3);
      game.inPark = true;
      expect(game.recallWait(), isTrue);
      game = PetGame.decode(game.encode());
      expect(game.recallWait(), isFalse);
      expect(game.waitRecalledAt, secondVisit);

      game.advance(firstEvening.add(hour * 49));
      expect(game.alive, isTrue);
      expect(game.availableEndings, isEmpty);
      game.inPark = false;
      expect(game.clean(), isTrue);
      expect(game.feed(apple: false), isTrue);
      expect((game.affection, game.level), (5, 5));
      expect(game.availableEndings, [PetEnding.lastDisc, PetEnding.window]);
      expect(game.finish(PetEnding.stars), isFalse);
      expect(game.finish(PetEnding.lastDisc), isTrue);
      expect(game.finish(PetEnding.window), isFalse);

      game = PetGame.decode(game.encode());
      expect(game.ending, PetEnding.lastDisc);
      expect(game.keepsake, (from: PetKind.dongle, ending: PetEnding.lastDisc));
      final next = PetGame(game.at, kind: PetKind.leaf)
        ..keepsake = game.keepsake;
      expect(next.waitTaughtAt, isNull);
      expect(next.ending, isNull);
      expect(PetGame.decode(next.encode()).keepsake, game.keepsake);
    },
  );

  test('three different star days earn the constellation ending', () {
    final game = PetGame(firstEvening)..level = 5;
    expect(game.findStar(name: '우리 첫 별'), '우리 첫 별');
    expect(game.findStar(), isNull);
    for (var day = 1; day < PetGame.starNames.length; day++) {
      game.at = firstEvening.add(Duration(days: day));
      expect(game.findStar(), PetGame.starNames[day]);
    }
    final restored = PetGame.decode(game.encode());
    expect(restored.starTitles, ['우리 첫 별', ...PetGame.starNames.skip(1)]);
    expect(restored.availableEndings, [PetEnding.stars, PetEnding.window]);
    expect(restored.findStar(), isNull);
    expect(restored.finish(PetEnding.stars), isTrue);
  });

  test('park preferences, taught search and keepsake survive restoration', () {
    final active = PetGame(firstEvening, personality: const PetPersonality(2))
      ..inPark = true
      ..discs.add(const PetDisc(2, 2));
    final curious = PetGame(firstEvening, personality: const PetPersonality(4));
    expect(curious.feed(apple: false), isTrue);
    curious.inPark = true;
    final quiet = PetGame(firstEvening, personality: const PetPersonality(0))
      ..inPark = true;
    expect(active.parkIdea, PetParkIdea.disc);
    expect(quiet.parkIdea, PetParkIdea.rest);
    expect(curious.play(PetPlay.walk), isNotNull);
    expect(curious.parkIdea, PetParkIdea.search);

    final firstSpot = curious.searchSpot;
    final wrongSpot = PetSearchSpot.values.firstWhere(
      (spot) => spot != firstSpot,
    );
    expect(curious.findPinecone(wrongSpot, teach: true), isFalse);
    expect(curious.searchTaughtAt, isNull);
    expect(curious.findPinecone(firstSpot, teach: true), isTrue);
    expect(curious.findPinecone(firstSpot, teach: true), isFalse);
    expect(curious.recallSearch(), isFalse);

    final restored = PetGame.decode(curious.encode());
    restored.advance(firstEvening.add(hour * 15));
    expect(restored.searchSpot, isNot(firstSpot));
    expect(restored.recallSearch(), isTrue);
    expect(restored.recallWait(), isFalse);
    expect(restored.taughtSearchSpot, firstSpot);
    restored.level = 5;
    expect(restored.finish(PetEnding.pinecone), isTrue);
    final next = PetGame(restored.at)..keepsake = restored.keepsake;
    expect(next.useKeepsake(), isTrue);
    expect(next.useKeepsake(), isFalse);
    next.inPark = true;
    expect(next.canFindPinecone, isTrue);
    expect(PetGame.decode(next.encode()).keepsakeUsed, isTrue);
  });

  test(
    'meal previews use the actual schedule and leave the original untouched',
    () {
      final game = PetGame(firstEvening)
        ..fullness = 0
        ..hungerDeadline = firstEvening.add(PetGame.hungerGrace)
        ..nextHunger = null;
      final before = game.encode();
      final two = game.previewMeal(apple: false, portions: 2)!;
      expect(two.fullness, 2);
      expect(two.waste, 2);
      expect(two.hungryAt, firstEvening.add(hour * 12));
      expect(two.unattendedDeadline, firstEvening.add(hour * 30));
      expect(two.risk, '굶주림');
      final three = game.previewMeal(apple: false, portions: 3)!;
      expect(three.waste, 3);
      expect(three.unattendedDeadline, firstEvening.add(hour * 16));
      expect(three.risk, '위생 악화');
      expect(game.previewMeal(apple: false, portions: 4), isNull);
      expect(game.encode(), before);

      expect(game.feed(apple: false), isTrue);
      expect(game.feed(apple: false), isTrue);
      expect(game.digestion.first, two.nextWaste);
      game.advance(two.hungryAt);
      expect(game.fullness, 0);
      expect(game.waste, two.waste);
    },
  );

  test('rooms, the shortcut and disc lanes unlock at different levels', () {
    final game = PetGame(firstEvening)
      ..level = 2
      ..inPark = true
      ..discs.add(const PetDisc(4, 4));
    final energy = game.energy;
    expect(game.play(PetPlay.walk, route: PetParkRoute.shortcut), isNull);
    expect(game.play(PetPlay.disc, lane: PetDiscLane.far), isNull);
    expect(game.energy, energy);
    expect(game.play(PetPlay.walk), isNotNull);
    expect(game.findPinecone(game.searchSpot), isTrue);
    expect(game.canFindPinecone, isFalse);
    expect(game.placePinecone(PetRoomSpot.window), isFalse);

    game.inPark = false;
    expect(game.placePinecone(PetRoomSpot.window), isTrue);
    expect(game.placePinecone(PetRoomSpot.window), isFalse);
    expect(game.placePinecone(PetRoomSpot.rug), isTrue);
    final legacy = jsonDecode(game.encode()) as Map<String, dynamic>
      ..remove('pineconeSpot')
      ..remove('lastMainSearchAt')
      ..['placedPinecone'] = true;
    final restored = PetGame.decode(jsonEncode(legacy));
    expect(restored.pineconeSpot, PetRoomSpot.rug);
    expect(restored.lastMainSearchAt, firstEvening);
    restored.inPark = true;
    restored.level = 3;
    expect(restored.canFindPinecone, isFalse);
    expect(
      restored.play(PetPlay.walk, route: PetParkRoute.shortcut),
      isNotNull,
    );
    expect(restored.reachableSearchSpots, [PetSearchSpot.grove]);
    expect(restored.findPinecone(PetSearchSpot.bench), isFalse);
    expect(restored.findPinecone(PetSearchSpot.grove), isTrue);
    expect(restored.canFindPinecone, isFalse);
    final afterWalk = PetGame.decode(restored.encode());
    expect(afterWalk.parkRoute, PetParkRoute.shortcut);
    expect(afterWalk.canFindPinecone, isFalse);
    expect(afterWalk.canThrowLane(PetDiscLane.far), isFalse);

    afterWalk.level = 4;
    final before = afterWalk.energy;
    expect(afterWalk.play(PetPlay.disc, lane: PetDiscLane.far), isNotNull);
    expect(afterWalk.play(PetPlay.disc, lane: PetDiscLane.near), isNotNull);
    expect(afterWalk.energy, before - PetPlay.disc.cost * 2);
    expect(afterWalk.discs.single.remaining, 2);
  });

  test('room offers are saved per spot and defer while the pet needs care', () {
    final game = PetGame(firstEvening)
      ..pineconeSpot = PetRoomSpot.window
      ..inPark = true;
    expect(game.takeRoomOffer(), isNull);
    game.inPark = false;
    game.waste = 3;
    expect(game.takeRoomOffer(), isNull);
    game.waste = 0;
    expect(game.takeRoomOffer(), PetRoomSpot.window);
    expect(game.takeRoomOffer(), isNull);

    final restored = PetGame.decode(game.encode());
    expect(restored.takeRoomOffer(), isNull);
    restored.pineconeSpot = PetRoomSpot.rug;
    expect(restored.takeRoomOffer(), PetRoomSpot.rug);
    restored.pineconeSpot = PetRoomSpot.window;
    expect(restored.takeRoomOffer(), isNull);
    restored.at = firstEvening.add(hour * 24);
    expect(restored.takeRoomOffer(), PetRoomSpot.window);

    final legacy = jsonDecode(game.encode()) as Map<String, dynamic>
      ..remove('roomOfferDays')
      ..remove('shortcutGuided');
    final fromLegacy = PetGame.decode(jsonEncode(legacy));
    expect(fromLegacy.shortcutGuided, isFalse);
    expect(fromLegacy.takeRoomOffer(), PetRoomSpot.window);
    fromLegacy.shortcutGuided = true;
    expect(PetGame.decode(fromLegacy.encode()).shortcutGuided, isTrue);
  });

  test('older saves keep the original pet and get default abilities', () {
    final original = PetGame(firstEvening)..energy = 123;
    final oldSave = jsonDecode(original.encode()) as Map<String, dynamic>;
    for (final field in [
      'kind',
      'raisedKinds',
      'personality',
      'confidence',
      'agility',
      'curiosity',
    ]) {
      oldSave.remove(field);
    }
    oldSave.remove('discs');
    oldSave['disc'] = true;
    final restored = PetGame.decode(jsonEncode(oldSave));
    expect((restored.kind, restored.energy), (PetKind.dongle, 123));
    expect(restored.raisedKinds, unorderedEquals([PetKind.dongle]));
    expect(
      restored.personality.code,
      PetGame.decode(jsonEncode(oldSave)).personality.code,
    );
    expect(
      (restored.discs.single.maximum, restored.discs.single.remaining),
      (3, 3),
    );
    expect(
      (restored.confidence, restored.agility, restored.curiosity),
      (5, 0, 0),
    );
  });

  test('bench recovery is limited by time and persists across reloads', () {
    final game = PetGame(firstEvening)..energy = 300;
    expect(game.recoverAtBench(), 0);
    game.inPark = true;
    expect(game.recoverAtBench(), 32);
    expect(game.energy, 332);
    final restored = PetGame.decode(game.encode());
    expect(restored.recoverAtBench(), 0);
    restored.advance(firstEvening.add(const Duration(minutes: 10)));
    expect(restored.recoverAtBench(), 32);
    restored.advance(firstEvening.add(const Duration(minutes: 20)));
    expect(restored.recoverAtBench(), 20);
    expect(restored.energy, restored.maxEnergy);
  });

  test(
    'the sixteen personality combinations have distinct persisted codes',
    () {
      final codes = <String>{};
      for (var bits = 0; bits < 16; bits++) {
        final game = PetGame(firstEvening, personality: PetPersonality(bits));
        final restored = PetGame.decode(game.encode());
        expect(restored.personality.traits, game.personality.traits);
        codes.add(restored.personality.code);
      }
      expect(codes, hasLength(16));
    },
  );

  test(
    'a recalled photo play keeps the actual disc and landing after reload',
    () {
      final game = PetGame(firstEvening)
        ..level = 4
        ..inPark = true;
      final first = game.addFinds(
        '벚꽃 산책',
        apple: false,
        frisbee: true,
        random: const _Roll(10),
      )!;
      final second = game.addFinds(
        '벤치 사진',
        apple: false,
        frisbee: true,
        random: const _Roll(90),
      )!;
      expect(first.id, isNot(second.id));
      expect(game.selectPhotoDisc(first.id!), isTrue);
      expect(
        game.play(PetPlay.disc, lane: PetDiscLane.far, teachWait: true),
        isNotNull,
      );
      game.addFinds('놀이 후에 가져온 사진', apple: false, frisbee: false);
      final restored = PetGame.decode(game.encode());
      restored.advance(firstEvening.add(hour * 15));
      final memory = restored.nextMemory!;
      expect(
        (memory.title, memory.discId, memory.discLane),
        ('벚꽃 산책', first.id, PetDiscLane.far),
      );
      expect(restored.waitMemory?.key, memory.key);
      expect(restored.hasMemoryDisc(memory), isTrue);
      restored.inPark = false;
      expect(restored.feed(apple: false), isTrue);
      restored.inPark = true;
      expect(restored.selectPhotoDisc(memory.discId!), isTrue);
      expect(restored.play(PetPlay.disc)!.discBroke, isTrue);
      expect(restored.discs.single.id, second.id);
      expect(restored.hasMemoryDisc(memory), isFalse);
      expect(restored.selectPhotoDisc(memory.discId!), isFalse);
    },
  );

  test('a keepsake can open a room activity instead of the outdoor lesson', () {
    final game = PetGame(firstEvening)
      ..keepsake = (from: PetKind.dongle, ending: PetEnding.lastDisc);
    expect(game.useKeepsakeAtHome(), isTrue);
    expect(game.agility, 1);
    expect(game.discs, isEmpty);
    expect(game.memories.single.title, '우리 방에서 만난 작은 원반');
    final restored = PetGame.decode(game.encode());
    expect(restored.canUseKeepsakeAtHome, isFalse);
    expect(restored.useKeepsake(), isFalse);

    final stars = PetGame(firstEvening)
      ..keepsake = (from: PetKind.leaf, ending: PetEnding.stars);
    expect(stars.canUseKeepsake, isFalse);
    expect(stars.useKeepsakeAtHome(), isTrue);
    expect(stars.curiosity, 1);
  });

  test('each photo rolls a disc and only a completed throw consumes a use', () {
    final game = PetGame(firstEvening)..level = 2;
    for (final (roll, expected) in [
      (0, 1),
      (9, 1),
      (10, 2),
      (29, 2),
      (30, 3),
      (64, 3),
      (65, 4),
      (89, 4),
      (90, 5),
      (99, 5),
    ]) {
      final disc = game.addFinds(
        '',
        apple: false,
        frisbee: true,
        random: _Roll(roll),
      )!;
      expect((disc.maximum, disc.remaining), (expected, expected));
    }
    final restored = PetGame.decode(game.encode())
      ..inPark = true
      ..energy = 31;
    expect(restored.play(PetPlay.disc), isNull);
    expect(restored.discs.length, 10);
    restored.energy = 384;
    expect(restored.play(PetPlay.disc)?.discBroke, isTrue);
    expect(restored.discs.length, 9);
    expect(restored.play(PetPlay.disc)?.discBroke, isTrue);
    expect(restored.play(PetPlay.disc)?.discBroke, isFalse);
    expect(
      (restored.discs.first.maximum, restored.discs.first.remaining),
      (2, 1),
    );
  });
}

class _Roll implements math.Random {
  const _Roll(this.value);
  final int value;
  @override
  int nextInt(int max) => value;
  @override
  bool nextBool() => throw UnsupportedError('Only integer rolls are used');
  @override
  double nextDouble() => throw UnsupportedError('Only integer rolls are used');
}
