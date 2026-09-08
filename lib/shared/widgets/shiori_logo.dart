import 'package:flutter/material.dart';
import '../../l10n/generated/app_localizations.dart';

/// One transparent master keeps both theme variants geometrically identical.
class ShioriLogo extends StatelessWidget {
  const ShioriLogo({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    Widget image = Image.asset(
      'assets/brand/shiori.png',
      width: 1942,
      height: 809,
      filterQuality: FilterQuality.high,
      excludeFromSemantics: true,
    );
    if (theme.brightness == Brightness.dark) {
      image = ShaderMask(
        blendMode: BlendMode.srcATop,
        shaderCallback: (bounds) => const LinearGradient(
          colors: [
            Colors.transparent,
            Colors.transparent,
            Color(0xffeee7eb),
            Color(0xffeee7eb),
          ],
          // The gap between bookmark and lettering in the approved master.
          stops: [0, .32, .32, 1],
        ).createShader(bounds),
        child: image,
      );
    }
    return Semantics(
      label: AppLocalizations.of(context).appTitle,
      image: true,
      child: SizedBox(
        width: 128,
        height: 34,
        child: FittedBox(
          fit: BoxFit.contain,
          alignment: Alignment.centerLeft,
          child: ClipRect(
            child: Align(
              alignment: Alignment.center,
              widthFactor: .64,
              heightFactor: .42,
              child: image,
            ),
          ),
        ),
      ),
    );
  }
}
