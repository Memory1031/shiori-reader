import 'package:flutter/material.dart';

import '../../app/theme/shiori_theme.dart';
import '../../domain/contracts/local_book_decoder.dart';
import '../../l10n/generated/app_localizations.dart';

String txtEncodingName(TxtEncoding encoding) => switch (encoding) {
  TxtEncoding.utf8 => 'UTF-8',
  TxtEncoding.utf16le => 'UTF-16 LE',
  TxtEncoding.utf16be => 'UTF-16 BE',
  TxtEncoding.gb18030 => 'GB18030 / GBK',
};

class TxtPreviewChoices extends StatelessWidget {
  const TxtPreviewChoices({
    super.key,
    required this.preview,
    required this.onChoice,
  });

  final TxtEncodingPreview preview;
  final ValueChanged<TxtEncoding> onChoice;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(l.importEncodingHint),
        for (final entry in preview.samples.entries) ...[
          const Padding(
            padding: EdgeInsets.symmetric(vertical: ShioriSpace.small),
            child: Divider(),
          ),
          Text(entry.value, style: Theme.of(context).textTheme.bodyLarge),
          const SizedBox(height: ShioriSpace.small),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: OutlinedButton(
              key: ValueKey(entry.key),
              onPressed: () => onChoice(entry.key),
              child: Text(l.importUseText),
            ),
          ),
        ],
      ],
    );
  }
}
