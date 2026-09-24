import 'package:flutter/material.dart';
import 'theme/shiori_theme.dart';
import '../l10n/generated/app_localizations.dart';

/// Shown only while real initialization is pending; no artificial startup delay.
class LaunchView extends StatelessWidget {
  const LaunchView({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final l = AppLocalizations.of(context);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(ShioriSpace.section),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ExcludeSemantics(
                  child: Container(
                    width: 208,
                    height: 208,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(
                        colors: [
                          colors.primary.withValues(alpha: .10),
                          colors.primary.withValues(alpha: .025),
                          colors.primary.withValues(alpha: 0),
                        ],
                      ),
                    ),
                    child: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: colors.surface,
                        borderRadius: BorderRadius.circular(30),
                        border: Border.all(
                          color: colors.outlineVariant.withValues(alpha: .5),
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: colors.shadow.withValues(alpha: .07),
                            blurRadius: 24,
                            offset: const Offset(0, 10),
                          ),
                        ],
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(24),
                        child: Image.asset(
                          'assets/branding/shiori-chibi-logo-v1.png',
                          width: 128,
                          height: 128,
                          cacheWidth:
                              (128 * MediaQuery.devicePixelRatioOf(context))
                                  .ceil(),
                          fit: BoxFit.contain,
                          filterQuality: FilterQuality.high,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: ShioriSpace.tight),
                Text('Shiori', style: ShioriType.of(context).brand),
                const SizedBox(height: ShioriSpace.small),
                Text(
                  l.launchTagline,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: ShioriSpace.section),
                SizedBox(
                  width: 80,
                  child: LinearProgressIndicator(
                    minHeight: 2,
                    value: MediaQuery.disableAnimationsOf(context) ? .5 : null,
                    backgroundColor: colors.outlineVariant.withValues(
                      alpha: .4,
                    ),
                    color: colors.primary.withValues(alpha: .65),
                    semanticsLabel: l.launchLoading,
                  ),
                ),
                const SizedBox(height: 14),
                Text(l.launchLoading, style: theme.textTheme.bodySmall),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
