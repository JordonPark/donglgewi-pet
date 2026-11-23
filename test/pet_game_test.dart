import 'package:flutter_test/flutter_test.dart';
import 'package:donglgewi/pet/pet_game.dart';

void main() {
  final firstEvening = DateTime(2026, 11, 23, 18);

  PetGame firstVisit() {
    final game = PetGame(firstEvening);
    game.addFinds('공원 소풍', apple: true, frisbee: true);
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
    expect(game.energy, 430);
    game.advance(firstEvening.add(const Duration(minutes: 30)));
    expect(game.energy, 448);
    final steady = PetGame.decode(game.encode());
    expect((steady.energy, steady.affection, steady.level), (448, 3, 2));
  });
}
