/*
 * This file is part of wger Workout Manager <https://github.com/wger-project>.
 * Copyright (c) 2020 - 2026 wger Team
 *
 * wger Workout Manager is free software: you can redistribute it and/or modify
 * it under the terms of the GNU Affero General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU Affero General Public License for more details.
 *
 * You should have received a copy of the GNU Affero General Public License
 * along with this program.  If not, see <http://www.gnu.org/licenses/>.
 */

import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wger/core/formatting/formatting.dart';
import 'package:wger/core/network/network_provider.dart';
import 'package:wger/core/widgets/async_value_widget.dart';
import 'package:wger/core/widgets/confirm_delete_dialog.dart';
import 'package:wger/core/widgets/text_prompt.dart';
import 'package:wger/features/routines/providers/routines_notifier.dart';
import 'package:wger/features/routines/screens/routine_screen.dart';
import 'package:wger/l10n/generated/app_localizations.dart';
import 'package:wger/theme/motion.dart';
import 'package:wger/theme/spacing.dart';

class RoutinesList extends ConsumerStatefulWidget {
  const RoutinesList();

  @override
  ConsumerState<RoutinesList> createState() => _RoutinesListState();
}

class _RoutinesListState extends ConsumerState<RoutinesList> {
  int? _loadingRoutine;

  @override
  Widget build(BuildContext context) {
    final dateFormat = localizedDate(context);
    final routineProvider = ref.read(routinesRiverpodProvider.notifier);
    final routinesAsync = ref.watch(routinesRiverpodProvider);
    final isOnline = ref.watch(networkStatusProvider);

    return AsyncValueWidget<RoutinesState>(
      value: routinesAsync,
      loggerName: 'RoutinesList',
      data: (state) {
        final routines = state.routines;
        if (routines.isEmpty) {
          return const TextPrompt();
        }
        return ListView.builder(
          padding: const EdgeInsets.all(10.0),
          itemCount: routines.length,
          itemBuilder: (context, index) {
            final currentRoutine = routines[index];
            final routineId = currentRoutine.id!;
            final i18n = AppLocalizations.of(context);
            final colorScheme = Theme.of(context).colorScheme;

            // The routine structure is fetched via REST. Offline it can only
            // be opened if it was already loaded earlier
            final canOpen = isOnline || currentRoutine.isHydrated;

            final now = clock.now();
            final isActive =
                !now.isBefore(currentRoutine.start) && !now.isAfter(currentRoutine.end);

            return Card(
              margin: const EdgeInsets.only(bottom: AppSpacing.sm),
              clipBehavior: Clip.antiAlias,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: isActive
                    ? BorderSide(color: colorScheme.primary, width: 2)
                    : BorderSide.none,
              ),
              child: InkWell(
                onTap: canOpen
                    ? () async {
                        if (isOnline) {
                          setState(() {
                            _loadingRoutine = routineId;
                          });
                          try {
                            await routineProvider.fetchAndSetRoutineFull(routineId);
                          } finally {
                            if (mounted) {
                              setState(() => _loadingRoutine = null);
                            }
                          }
                        }

                        if (context.mounted) {
                          Navigator.of(context).pushNamed(
                            RoutineScreen.routeName,
                            arguments: routineId,
                          );
                        }
                      }
                    : null,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.lg,
                    vertical: AppSpacing.md,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    currentRoutine.name,
                                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                      fontWeight: FontWeight.bold,
                                      color: canOpen ? null : colorScheme.onSurface.withValues(
                                        alpha: 0.4,
                                      ),
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                if (isActive)
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: AppSpacing.sm,
                                      vertical: 2,
                                    ),
                                    decoration: BoxDecoration(
                                      color: colorScheme.primary.withValues(alpha: 0.14),
                                      borderRadius: BorderRadius.circular(999),
                                    ),
                                    child: Text(
                                      i18n.active,
                                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                        color: colorScheme.primary,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                            const SizedBox(height: AppSpacing.xs),
                            Row(
                              children: [
                                Icon(
                                  Icons.calendar_today_outlined,
                                  size: 14,
                                  color: colorScheme.onSurfaceVariant,
                                ),
                                const SizedBox(width: AppSpacing.xs),
                                Text(
                                  '${dateFormat.format(currentRoutine.start)}'
                                  ' - ${dateFormat.format(currentRoutine.end)}',
                                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: colorScheme.onSurfaceVariant,
                                  ),
                                ),
                                if (!canOpen) ...[
                                  const SizedBox(width: AppSpacing.sm),
                                  Icon(
                                    Icons.cloud_off,
                                    size: 14,
                                    color: colorScheme.onSurfaceVariant,
                                  ),
                                ],
                              ],
                            ),
                          ],
                        ),
                      ),
                      if (_loadingRoutine == currentRoutine.id)
                        const Padding(
                          padding: EdgeInsets.symmetric(horizontal: AppSpacing.sm),
                          child: SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        )
                      else
                        IconButton(
                          icon: const Icon(Icons.delete_outline),
                          tooltip: i18n.delete,
                          onPressed: () => showConfirmDeleteDialog(
                            context,
                            itemName: currentRoutine.name,
                            onConfirm: () => routineProvider.deleteRoutine(currentRoutine.id!),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            )
                .animate()
                .fadeIn(
                  duration: AppMotion.standard,
                  delay: Duration(milliseconds: 30 * index.clamp(0, 10)),
                )
                .slideY(
                  begin: 0.05,
                  end: 0,
                  duration: AppMotion.standard,
                  curve: AppMotion.standardCurve,
                );
          },
        );
      },
    );
  }
}
