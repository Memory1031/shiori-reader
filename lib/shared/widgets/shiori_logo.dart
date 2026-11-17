import 'package:flutter/material.dart';
import '../../l10n/generated/app_localizations.dart';

Widget _brandMaster() => Image.asset(
  'assets/brand/shiori.png',
  width: 1942,
  height: 809,
  filterQuality: FilterQuality.high,
  excludeFromSemantics: true,
);

/// One transparent master keeps both theme variants geometrically identical.
class ShioriLogo extends StatelessWidget {
  const ShioriLogo({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    var image = _brandMaster();
    if (theme.brightness == Brightness.dark) {
      final ink = theme.colorScheme.onSurface;
      image = ShaderMask(
        blendMode: BlendMode.srcATop,
        shaderCallback: (bounds) => LinearGradient(
          colors: [Colors.transparent, Colors.transparent, ink, ink],
          // The gap between bookmark and lettering in the approved master.
          stops: const [0, .32, .32, 1],
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

/// Compact bookmark mark extracted from the same transparent master for rail layout.
class ShioriMark extends StatelessWidget {
  const ShioriMark({super.key});

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: SizedBox(
      width: 28,
      height: 28,
      child: FittedBox(
        fit: BoxFit.contain,
        child: ClipRect(
          child: Align(
            alignment: const Alignment(-0.577, 0),
            widthFactor: .1236,
            heightFactor: .42,
            child: _brandMaster(),
          ),
        ),
      ),
    ),
  );
}
