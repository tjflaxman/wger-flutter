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
import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';
import 'package:wger/core/date.dart';
import 'package:wger/core/network/network_provider.dart';
import 'package:wger/core/widgets/error.dart';
import 'package:wger/core/widgets/progress_indicator.dart';
import 'package:wger/features/routines/models/session.dart';
import 'package:wger/features/routines/providers/gym_state_notifier.dart';
import 'package:wger/features/routines/providers/routines_notifier.dart';
import 'package:wger/features/routines/widgets/gym_mode/navigation.dart';
import 'package:wger/features/trophies/models/user_trophy.dart';
import 'package:wger/features/trophies/providers/trophy_notifier.dart';
import 'package:wger/l10n/generated/app_localizations.dart';
import 'package:wger/theme/motion.dart';
import 'package:wger/theme/spacing.dart';

import '../logs/exercises_expansion_card.dart';
import '../logs/muscle_groups.dart';

class WorkoutSummary extends ConsumerStatefulWidget {
  final _logger = Logger('WorkoutSummary');
  final PageController _controller;

  WorkoutSummary(this._controller);

  @override
  ConsumerState<WorkoutSummary> createState() => _WorkoutSummaryState();
}

class _WorkoutSummaryState extends ConsumerState<WorkoutSummary> {
  late Future<void> _trophyFuture;
  bool _didInit = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_didInit) {
      // Trophies are REST-only and only enrich the summary (PR count + markers).
      // Fetch them when the server is reachable; offline we skip the doomed
      // request so the local session stats render right away.
      if (ref.read(networkStatusProvider)) {
        final languageCode = Localizations.localeOf(context).languageCode;
        _trophyFuture = ref
            .read(trophyStateProvider.notifier)
            .fetchUserTrophies(language: languageCode);
      } else {
        _trophyFuture = Future<void>.value();
      }
      _didInit = true;
    }
  }

  @override
  Widget build(BuildContext context) {
    final routineId = ref.read(gymStateProvider).routine.id!;
    final routinesState = ref.watch(routinesRiverpodProvider).value;
    final routine = routinesState?.routines.firstWhereOrNull((r) => r.id == routineId);
    final trophyState = ref.watch(trophyStateProvider);

    return Column(
      children: [
        NavigationHeader(
          AppLocalizations.of(context).workoutCompleted,
          widget._controller,
          showEndWorkoutButton: false,
        ),
        Expanded(
          child: FutureBuilder<void>(
            future: _trophyFuture,
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                // An error reaching here is a genuine, unexpected exception worth surfacing
                widget._logger.warning(
                  'Could not fetch user trophies',
                  snapshot.error,
                  snapshot.stackTrace,
                );
                return StreamErrorIndicator(snapshot.error!, stacktrace: snapshot.stackTrace);
              }
              if (snapshot.connectionState == ConnectionState.waiting || routine == null) {
                return const BoxedProgressIndicator();
              }

              final session = routine.sessions.firstWhereOrNull(
                (s) => s.date.isSameDayAs(clock.now()),
              );
              final userTrophies = trophyState.prTrophies
                  .where((t) => t.contextData?.sessionId == session?.id)
                  .toList();

              return WorkoutSessionStats(session, userTrophies);
            },
          ),
        ),
        NavigationFooter(widget._controller, showNext: false),
      ],
    );
  }
}

class WorkoutSessionStats extends ConsumerWidget {
  final WorkoutSession? _session;
  final List<UserTrophy> _userPrTrophies;

  const WorkoutSessionStats(this._session, this._userPrTrophies, {super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final i18n = AppLocalizations.of(context);

    if (_session == null) {
      return Center(
        child: Text('Nothing logged yet.', style: Theme.of(context).textTheme.titleMedium),
      );
    }

    final sessionDuration = _session.duration;
    final totalVolume = _session.volume;

    /// We assume that users will do exercises (mostly) either in metric or imperial
    /// units so we just display the higher one.
    String volumeUnit;
    num volumeValue;
    if (totalVolume['metric']! > totalVolume['imperial']!) {
      volumeValue = totalVolume['metric']!;
      volumeUnit = i18n.kg;
    } else {
      volumeValue = totalVolume['imperial']!;
      volumeUnit = i18n.lb;
    }

    return ListView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      children: [
        _WorkoutHeroCard(
          durationText: sessionDuration != null
              ? i18n.durationHoursMinutes(
                  sessionDuration.inHours,
                  sessionDuration.inMinutes.remainder(60),
                )
              : '-/-',
          durationLabel: i18n.duration,
          volumeText: '${volumeValue.toStringAsFixed(0)} $volumeUnit',
          volumeLabel: i18n.volume,
        ).animate().fadeIn(duration: AppMotion.standard).slideY(
          begin: 0.08,
          end: 0,
          duration: AppMotion.standard,
          curve: AppMotion.standardCurve,
        ),
        if (_userPrTrophies.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.md),
            child:
                _PrTrophyCard(count: _userPrTrophies.length)
                    .animate()
                    .fadeIn(
                      delay: AppMotion.standard,
                      duration: AppMotion.standard,
                    )
                    .scale(
                      begin: const Offset(0.85, 0.85),
                      end: const Offset(1, 1),
                      delay: AppMotion.standard,
                      duration: AppMotion.standard,
                      curve: AppMotion.emphasizedCurve,
                    ),
          ),
        const SizedBox(height: AppSpacing.md),
        MuscleGroupsCard(_session.logs),
        const SizedBox(height: AppSpacing.md),
        ExercisesCard(_session, _userPrTrophies),
        const SizedBox(height: AppSpacing.md),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: () {
              ref.read(gymStateProvider.notifier).clear();
              Navigator.of(context).pop();
            },
            icon: const Icon(Icons.check),
            label: Text(i18n.endWorkout),
          ),
        ),
      ],
    );
  }
}

/// The top-of-summary hero: duration + volume as the two headline numbers,
/// on a single tinted card instead of two plain white ones, so the two
/// numbers that matter most read as a pair rather than a generic stat list.
class _WorkoutHeroCard extends StatelessWidget {
  final String durationLabel;
  final String durationText;
  final String volumeLabel;
  final String volumeText;

  const _WorkoutHeroCard({
    required this.durationLabel,
    required this.durationText,
    required this.volumeLabel,
    required this.volumeText,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final i18n = AppLocalizations.of(context);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.check_circle, color: colorScheme.onPrimaryContainer),
              const SizedBox(width: AppSpacing.sm),
              Text(
                i18n.workoutCompleted,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: colorScheme.onPrimaryContainer,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          Row(
            children: [
              Expanded(
                child: _HeroStat(
                  label: durationLabel,
                  value: durationText,
                  foreground: colorScheme.onPrimaryContainer,
                ),
              ),
              SizedBox(
                height: 40,
                child: VerticalDivider(
                  color: colorScheme.onPrimaryContainer.withValues(alpha: 0.3),
                ),
              ),
              Expanded(
                child: _HeroStat(
                  label: volumeLabel,
                  value: volumeText,
                  foreground: colorScheme.onPrimaryContainer,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _HeroStat extends StatelessWidget {
  final String label;
  final String value;
  final Color foreground;

  const _HeroStat({required this.label, required this.value, required this.foreground});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          value,
          style: theme.textTheme.headlineMedium?.copyWith(
            color: foreground,
            fontWeight: FontWeight.bold,
          ),
        ),
        Text(label, style: theme.textTheme.bodyMedium?.copyWith(color: foreground)),
      ],
    );
  }
}

/// A distinct, celebratory card for PR count -- separated visually from the
/// duration/volume stats (and animated in with a slight delay + pop/scale)
/// so a personal record actually reads as an event, not just another number.
class _PrTrophyCard extends StatelessWidget {
  final int count;

  const _PrTrophyCard({required this.count});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final i18n = AppLocalizations.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.md),
      decoration: BoxDecoration(
        color: colorScheme.tertiaryContainer,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        children: [
          Icon(Icons.emoji_events, color: colorScheme.onTertiaryContainer, size: 32),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  count.toString(),
                  style: theme.textTheme.headlineSmall?.copyWith(
                    color: colorScheme.onTertiaryContainer,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  i18n.personalRecords,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: colorScheme.onTertiaryContainer,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
