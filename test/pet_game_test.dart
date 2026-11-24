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
    game.play();
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
      expect(game.feed(apple: false), isTrue);
      expect(game.healthy, isTrue);
      expect(game.nextMemory?.title, '공원 소풍');
      expect(PetGame.decode(game.encode()).nextMemory?.title, '공원 소풍');
    },
  );

  test(
    'three queued meals tighten hygiene deadline and cleaning cancels it',
    () {
      final game = firstVisit();
      final secondEvening = firstEvening.add(hour * 24);
      game.advance(secondEvening);
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
      final disc = game.play(PetPlay.disc)!;
      expect(disc.gains, {'민첩': 1, '자신감': 1, '기분': 1});
      expect(game.energy, 352);

      game.inPark = true;
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

  test('older saves keep the original pet and get default abilities', () {
    final original = PetGame(firstEvening)..energy = 123;
    final oldSave = jsonDecode(original.encode()) as Map<String, dynamic>;
    for (final field in [
      'kind',
      'raisedKinds',
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
      (restored.discs.single.maximum, restored.discs.single.remaining),
      (3, 3),
    );
    expect(
      (restored.confidence, restored.agility, restored.curiosity),
      (5, 0, 0),
    );
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
    final restored = PetGame.decode(game.encode())..energy = 31;
    expect(restored.play(), isNull);
    expect(restored.discs.length, 10);
    restored.energy = 384;
    expect(restored.play()?.discBroke, isTrue);
    expect(restored.discs.length, 9);
    expect(restored.play()?.discBroke, isTrue);
    expect(restored.play()?.discBroke, isFalse);
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
