import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import 'pet_game.dart';
import 'pet_sprite.dart';

const petParkSearchPositions = {
  PetSearchSpot.bench: Offset(.62, .69),
  PetSearchSpot.tree: Offset(.79, .54),
  PetSearchSpot.path: Offset(.34, .75),
  PetSearchSpot.grove: Offset(.60, .37),
};

const petStarIcons = [
  Icons.star_rounded,
  Icons.auto_awesome,
  Icons.stars_rounded,
];

class PetFarewellScene extends StatelessWidget {
  const PetFarewellScene({super.key, required this.hunger});

  final bool hunger;

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(16),
    child: AspectRatio(
      aspectRatio: 1.5,
      child: LayoutBuilder(
        builder: (context, space) => TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: 1),
          duration: MediaQuery.disableAnimationsOf(context)
              ? Duration.zero
              : const Duration(milliseconds: 950),
          builder: (context, progress, _) => Stack(
            fit: StackFit.expand,
            children: [
              Image.asset(
                'assets/pet/room.png',
                fit: BoxFit.fill,
                excludeFromSemantics: true,
              ),
              ColoredBox(
                color: const Color(
                  0xff453441,
                ).withValues(alpha: .22 * progress),
              ),
              Positioned(
                left: space.maxWidth * (hunger ? .29 : .72) - 16,
                top: space.maxHeight * .77 - 12,
                child: Opacity(
                  opacity: progress,
                  child: Semantics(
                    label: hunger ? '비어 있는 그릇' : '치우지 못한 방',
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: const Color(0xfff8eadb),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(5),
                        child: Icon(
                          hunger
                              ? Icons.rice_bowl_outlined
                              : Icons.cleaning_services_outlined,
                          color: const Color(0xff583c2f),
                          size: 21,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class PetEndingScene extends StatelessWidget {
  const PetEndingScene({
    super.key,
    required this.kind,
    required this.ending,
    this.searchSpot,
  });

  final PetKind kind;
  final PetEnding ending;
  final PetSearchSpot? searchSpot;

  @override
  Widget build(BuildContext context) {
    final disc = ending == PetEnding.lastDisc;
    final searching = ending == PetEnding.pinecone;
    final park = disc || searching;
    final destination =
        petParkSearchPositions[searchSpot] ??
        petParkSearchPositions[PetSearchSpot.tree]!;
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: AspectRatio(
        aspectRatio: 1.5,
        child: LayoutBuilder(
          builder: (context, space) => TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: 1),
            duration: const Duration(milliseconds: 2300),
            builder: (context, time, _) {
              final waiting = disc && time < .40;
              final searchProgress = Curves.easeInOut.transform(
                ((time - .26) / .60).clamp(0.0, 1.0),
              );
              final outward = ((time - .40) / .30).clamp(0.0, 1.0);
              final back = ((time - .70) / .30).clamp(0.0, 1.0);
              final x = searching
                  ? .52 + (destination.dx - .52) * searchProgress
                  : disc
                  ? .52 +
                        .27 * Curves.easeInOut.transform(outward) -
                        .27 * Curves.easeInOut.transform(back)
                  : .52 + .12 * Curves.easeOut.transform(time);
              final y = searching
                  ? .64 + (destination.dy - .64) * searchProgress
                  : disc
                  ? .64 - .07 * math.sin(outward * math.pi)
                  : .73;
              final petWidth = space.maxWidth * .20;
              return Stack(
                fit: StackFit.expand,
                children: [
                  Image.asset(
                    park ? 'assets/pet/park.png' : 'assets/pet/room.png',
                    fit: BoxFit.fill,
                    excludeFromSemantics: true,
                  ),
                  if (disc && time >= .40)
                    Positioned(
                      left: space.maxWidth * (time < .70 ? .79 : x + .07) - 10,
                      top: space.maxHeight * .68,
                      child: const Icon(
                        Icons.trip_origin,
                        color: Color(0xffb95125),
                        size: 20,
                      ),
                    ),
                  if (searching && time > .80)
                    Positioned(
                      left: space.maxWidth * destination.dx + 4,
                      top: space.maxHeight * destination.dy - 16,
                      child: const Icon(
                        Icons.eco,
                        color: Color(0xff78452d),
                        size: 23,
                      ),
                    ),
                  if (ending == PetEnding.stars)
                    for (final (i, x) in [.39, .51, .64].indexed)
                      if (time >= .20 + i * .21)
                        Positioned(
                          left: space.maxWidth * x - 12,
                          top: space.maxHeight * (i == 1 ? .18 : .28),
                          child: Icon(
                            petStarIcons[i],
                            color: const Color(0xfffff3a6),
                            size: 24,
                          ),
                        ),
                  Positioned(
                    left: space.maxWidth * x - petWidth / 2,
                    top: space.maxHeight * y - petWidth * .65,
                    width: petWidth,
                    height: petWidth * .72,
                    child: AnimatedScale(
                      scale: waiting ? .91 : 1,
                      duration: const Duration(milliseconds: 180),
                      alignment: Alignment.bottomCenter,
                      child: PetSprite(
                        kind: kind,
                        stage: PetStage.adult,
                        blink: waiting && time > .28,
                      ),
                    ),
                  ),
                  if (searching && time < .38)
                    const Positioned(
                      left: 8,
                      bottom: 8,
                      child: Chip(label: Text('찾아봐')),
                    ),
                  if (waiting)
                    const Positioned(
                      bottom: 8,
                      left: 8,
                      child: Chip(label: Text('기다려')),
                    ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}
