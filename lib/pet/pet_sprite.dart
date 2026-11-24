import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import 'pet_game.dart';

class PetSprite extends StatelessWidget {
  const PetSprite({super.key, required this.kind, this.blink = false});

  final PetKind kind;
  final bool blink;

  @override
  Widget build(BuildContext context) {
    // The blink drawings share the same floor anchors, 480 pixels to the right.
    final openFrame = switch (kind) {
      PetKind.dongle => const Rect.fromLTRB(85, 138, 481, 446),
      PetKind.leaf => const Rect.fromLTRB(95, 606, 424, 932),
      PetKind.star => const Rect.fromLTRB(73, 1111, 486, 1417),
    };
    final frame = blink ? openFrame.translate(480, 0) : openFrame;
    return LayoutBuilder(
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
                    width: 1024 * scale,
                    height: 1536 * scale,
                    child: Image.asset(
                      'assets/pet/pet-blink-atlas.png',
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
    );
  }
}
