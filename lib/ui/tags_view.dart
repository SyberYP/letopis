import 'dart:math';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/strings.dart';
import '../state/app_state.dart';
import 'home_screen.dart';

/// Tag cloud: bigger chips for frequent tags.
class TagsView extends StatelessWidget {
  const TagsView({super.key, required this.onTag});
  final ValueChanged<String> onTag;

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final cs = Theme.of(context).colorScheme;
    final tags = app.store?.tagCounts() ?? const [];
    final top = tags.isEmpty ? 1 : tags.first.value;
    return CustomScrollView(
      slivers: [
        SliverAppBar(pinned: true, title: Text(tr('tags')), actions: commonActions(context)),
        if (tags.isEmpty)
          SliverFillRemaining(
            hasScrollBody: false,
            child: Padding(
              padding: const EdgeInsets.all(40),
              child: Center(
                child: Text(
                  tr('no_tags'),
                  textAlign: TextAlign.center,
                  style: TextStyle(color: cs.onSurfaceVariant),
                ),
              ),
            ),
          )
        else
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
            sliver: SliverToBoxAdapter(
              child: Wrap(
                spacing: 8,
                runSpacing: 10,
                children: [
                  for (final t in tags)
                    ActionChip(
                      onPressed: () => onTag(t.key),
                      backgroundColor: Color.lerp(cs.surfaceContainerHigh, cs.primaryContainer, _weight(t.value, top)),
                      label: Text.rich(
                        TextSpan(
                          children: [
                            TextSpan(
                              text: '#${t.key}',
                              style: TextStyle(
                                fontSize: 13 + 6 * _weight(t.value, top),
                                fontWeight: FontWeight.w600,
                                color: cs.onPrimaryContainer,
                              ),
                            ),
                            TextSpan(
                              text: '  ${t.value}',
                              style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  static double _weight(int n, int top) => top <= 1 ? 0.3 : (log(n) / log(top)).clamp(0.0, 1.0);
}
