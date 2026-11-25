import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import 'pet_game.dart';

class PetSprite extends StatelessWidget {
  const PetSprite({
    super.key,
    required this.kind,
    this.stage = PetStage.baby,
    this.blink = false,
  });

  final PetKind kind;
  final PetStage stage;
  final bool blink;

  // Each growth pair shares a baseline and scale, including while blinking.
  static const _growthFrames = [
    [
      Rect.fromLTWH(54, 86, 260, 240),
      Rect.fromLTWH(404, 86, 260, 240),
      Rect.fromLTWH(747, 80, 321, 246),
      Rect.fromLTWH(1111, 80, 321, 246),
    ],
    [
      Rect.fromLTWH(59, 423, 235, 239),
      Rect.fromLTWH(409, 423, 235, 239),
      Rect.fromLTWH(740, 404, 298, 261),
      Rect.fromLTWH(1102, 404, 298, 261),
    ],
    [
      Rect.fromLTWH(53, 758, 259, 227),
      Rect.fromLTWH(402, 758, 259, 227),
      Rect.fromLTWH(740, 745, 316, 245),
      Rect.fromLTWH(1104, 745, 316, 245),
    ],
  ];

  @override
  Widget build(BuildContext context) {
    // The blink drawings share the same floor anchors, 480 pixels to the right.
    final openFrame = switch (kind) {
      PetKind.dongle => const Rect.fromLTRB(85, 138, 481, 446),
      PetKind.leaf => const Rect.fromLTRB(95, 606, 424, 932),
      PetKind.star => const Rect.fromLTRB(73, 1111, 486, 1417),
    };
    final grown = stage != PetStage.baby;
    final frame = grown
        ? _growthFrames[kind.index][(stage == PetStage.adult ? 2 : 0) +
              (blink ? 1 : 0)]
        : blink
        ? openFrame.translate(480, 0)
        : openFrame;
    final atlas = grown ? 'pet-growth-atlas.png' : 'pet-blink-atlas.png';
    final atlasSize = grown ? const Size(1448, 1086) : const Size(1024, 1536);
    return AnimatedSwitcher(
      duration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : const Duration(milliseconds: 300),
      layoutBuilder: (current, previous) => Stack(
        alignment: Alignment.bottomCenter,
        children: [...previous, ?current],
      ),
      child: LayoutBuilder(
        key: ValueKey(stage),
        builder: (context, space) {
          final scale = math.min(
            space.maxWidth / frame.width,
            space.maxHeight / frame.height,
          );
          return Align(
            alignment: Alignment.bottomCenter,
            child: SizedBox(
              width: frame.width * scale,
              height: frame.height * scale,
              child: ClipRect(
                child: Stack(
                  children: [
                    Positioned(
                      left: -frame.left * scale,
                      top: -frame.top * scale,
                      width: atlasSize.width * scale,
                      height: atlasSize.height * scale,
                      child: Image.asset(
                        'assets/pet/$atlas',
                        fit: BoxFit.fill,
                        filterQuality: FilterQuality.none,
                        excludeFromSemantics: true,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
