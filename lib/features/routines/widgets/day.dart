/*
 * This file is part of wger Workout Manager <https://github.com/wger-project>.
 * Copyright (C) 2020, 2021 wger Team
 *
 * wger Workout Manager is free software: you can redistribute it and/or modify
 * it under the terms of the GNU Affero General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * wger Workout Manager is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU Affero General Public License for more details.
 *
 * You should have received a copy of the GNU Affero General Public License
 * along with this program.  If not, see <http://www.gnu.org/licenses/>.
 */

import 'package:flutter/material.dart';
import 'package:wger/core/date.dart';
import 'package:wger/core/widgets/core.dart';
import 'package:wger/features/exercises/models/exercise.dart';
import 'package:wger/features/exercises/widgets/exercises.dart';
import 'package:wger/features/exercises/widgets/images.dart';
import 'package:wger/features/routines/models/day_data.dart';
import 'package:wger/features/routines/models/slot_data.dart';
import 'package:wger/features/routines/screens/gym_mode.dart';
import 'package:wger/l10n/generated/app_localizations.dart';
import 'package:wger/theme/spacing.dart';

const _dayCardRadius = 16.0;

class SetConfigDataWidget extends StatelessWidget {
  final Exercise exercise;
  final Widget textRepetitionsWidget;

  const SetConfigDataWidget({required this.exercise, required this.textRepetitionsWidget});

  @override
  Widget build(BuildContext context) {
    final languageCode = Localizations.localeOf(context).languageCode;

    return ListTile(
      leading: InkWell(
        child: SizedBox(width: 45, child: ExerciseImageWidget(image: exercise.getMainImage)),
        onTap: () {
          showDialog(
            context: context,
            builder: (BuildContext context) {
              return AlertDialog(
                title: Text(exercise.getTranslation(languageCode).name),
                content: ExerciseDetail(exercise),
                actions: [
                  TextButton(
                    child: Text(MaterialLocalizations.of(context).closeButtonLabel),
                    onPressed: () {
                      Navigator.of(context).pop();
                    },
                  ),
                ],
              );
            },
          );
        },
      ),
      title: Text(exercise.getTranslation(languageCode).name),
      subtitle: textRepetitionsWidget,
    );
  }
}

class RoutineDayWidget extends StatelessWidget {
  final DayData _dayData;
  final int _routineId;
  final bool _viewMode;

  const RoutineDayWidget(this._dayData, this._routineId, this._viewMode);

  Widget getSlotDataRow(SlotData slotData, BuildContext context) {
    return Column(
      children: [
        if (slotData.comment.isNotEmpty) MutedText(slotData.comment),

        // If there's a single exercise with different sets, group them all into
        // the one exercise and don't show separate rows for each one.
        ...slotData.setConfigs
            .fold<Map<Exercise, List<String>>>({}, (acc, entry) {
              acc.putIfAbsent(entry.exercise, () => []).add(entry.textReprWithType);
              return acc;
            })
            .entries
            .map((entry) {
              return SetConfigDataWidget(
                exercise: entry.key,
                textRepetitionsWidget: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: entry.value.map((text) => Text(text)).toList(),
                ),
              );
            }),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final isToday = _dayData.date.isSameDayAs(DateTime.now());
    final isWorkoutDay = _dayData.day != null && !_dayData.day!.isRest;
    final colorScheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.only(left: 8, right: 8, bottom: 12),
      child: Card(
        margin: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(_dayCardRadius),
          side: isToday && isWorkoutDay
              ? BorderSide(color: colorScheme.primary, width: 2)
              : BorderSide.none,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            DayHeader(day: _dayData, routineId: _routineId, viewMode: _viewMode),
            ..._dayData.slots.map((e) => getSlotDataRow(e, context)),
          ],
        ),
      ),
    );
  }
}

class DayHeader extends StatelessWidget {
  final DayData _dayData;
  final int _routineId;
  final bool _viewMode;

  const DayHeader({required DayData day, required int routineId, bool viewMode = false})
    : _dayData = day,
      _viewMode = viewMode,
      _routineId = routineId;

  static Widget _todayChip(BuildContext context, {required Color foreground}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: AppSpacing.xs / 2),
      decoration: BoxDecoration(
        color: foreground.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        AppLocalizations.of(context).today.toUpperCase(),
        style: Theme.of(
          context,
        ).textTheme.labelSmall?.copyWith(color: foreground, fontWeight: FontWeight.bold),
      ),
    );
  }

  void _startWorkout(BuildContext context) {
    Navigator.of(context).pushNamed(
      GymModeScreen.routeName,
      arguments: GymModeArguments(_routineId, _dayData.day!.id!, _dayData.iteration),
    );
  }

  @override
  Widget build(BuildContext context) {
    final i18n = AppLocalizations.of(context);
    final colorScheme = Theme.of(context).colorScheme;
    final isToday = _dayData.date.isSameDayAs(DateTime.now());

    if (_dayData.day == null || _dayData.day!.isRest) {
      return ListTile(
        tileColor: Theme.of(context).focusColor,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        title: Text(
          i18n.restDay,
          style: Theme.of(context).textTheme.headlineSmall,
          overflow: TextOverflow.ellipsis,
        ),
        leading: const Icon(Icons.hotel),
        trailing: isToday ? _todayChip(context, foreground: colorScheme.onSurface) : null,
        minLeadingWidth: 8,
      );
    }

    // The workout day the user would actually open today gets a visually
    // distinct, higher-affordance header + a full-width CTA -- every other
    // day in the list stays a compact, tappable-but-secondary row so "what
    // should I do right now" doesn't require reading every card.
    if (isToday && !_viewMode) {
      return Container(
        decoration: BoxDecoration(
          color: colorScheme.primaryContainer,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(_dayCardRadius - 2),
            topRight: Radius.circular(_dayCardRadius - 2),
          ),
        ),
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.md,
          AppSpacing.lg,
          AppSpacing.lg,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    _dayData.day!.nameWithType,
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      color: colorScheme.onPrimaryContainer,
                      fontWeight: FontWeight.bold,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                _todayChip(context, foreground: colorScheme.onPrimaryContainer),
              ],
            ),
            if (_dayData.day!.description.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: AppSpacing.xs),
                child: Text(
                  _dayData.day!.description,
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(color: colorScheme.onPrimaryContainer),
                ),
              ),
            const SizedBox(height: AppSpacing.md),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: () => _startWorkout(context),
                icon: const Icon(Icons.play_arrow),
                label: Text(i18n.start),
              ),
            ),
          ],
        ),
      );
    }

    return ListTile(
      tileColor: Theme.of(context).focusColor,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      title: Text(
        _dayData.day!.nameWithType,
        style: Theme.of(context).textTheme.headlineSmall,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(_dayData.day!.description),
      leading: _viewMode ? null : const Icon(Icons.play_arrow),
      trailing: isToday ? _todayChip(context, foreground: colorScheme.onSurface) : null,
      minLeadingWidth: 8,
      onTap: _viewMode ? null : () => _startWorkout(context),
    );
  }
}
