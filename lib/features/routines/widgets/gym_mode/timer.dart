/*
 * This file is part of wger Workout Manager <https://github.com/wger-project>.
 * Copyright (C) 2020, 2025 wger Team
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
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:wger/features/routines/providers/gym_state_notifier.dart';
import 'package:wger/features/routines/services/rest_timer_notification_service.dart';
import 'package:wger/features/routines/widgets/gym_mode/navigation.dart';
import 'package:wger/l10n/generated/app_localizations.dart';
import 'package:wger/theme/motion.dart';
import 'package:wger/theme/theme.dart';

class TimerWidget extends StatefulWidget {
  final PageController _controller;

  const TimerWidget(this._controller);

  @override
  _TimerWidgetState createState() => _TimerWidgetState();
}

class _TimerWidgetState extends State<TimerWidget> {
  late DateTime _startTime;
  final _maxSeconds = 600;
  late Timer _uiTimer;

  @override
  void initState() {
    super.initState();
    _startTime = DateTime.now();

    _uiTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      // ignore: no-empty-block, avoid-empty-setstate
      if (mounted) {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _uiTimer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final elapsed = DateTime.now().difference(_startTime).inSeconds;
    final displaySeconds = elapsed > _maxSeconds ? _maxSeconds : elapsed;
    final displayTime = DateTime(2000, 1, 1, 0, 0, 0).add(Duration(seconds: displaySeconds));

    return Column(
      children: [
        NavigationHeader(
          AppLocalizations.of(context).pause,
          widget._controller,
        ),
        Expanded(
          child: Center(
            child: Text(
              DateFormat('m:ss').format(displayTime),
              style: Theme.of(context).textTheme.displayLarge!.copyWith(color: wgerPrimaryColor),
            ),
          ),
        ),
        NavigationFooter(widget._controller),
      ],
    );
  }
}

class TimerCountdownWidget extends ConsumerStatefulWidget {
  final PageController _controller;
  final int _seconds;

  const TimerCountdownWidget(
    this._controller,
    this._seconds,
  );

  @override
  _TimerCountdownWidgetState createState() => _TimerCountdownWidgetState();
}

class _TimerCountdownWidgetState extends ConsumerState<TimerCountdownWidget> {
  late DateTime _endTime;
  late Timer _uiTimer;

  // Only needs to be unique among notifications scheduled concurrently by
  // this app, which is at most one rest timer at a time.
  late final int _notificationId;
  bool _notificationScheduled = false;
  bool _hasFiredLocalAlert = false;

  @override
  void initState() {
    super.initState();
    _endTime = DateTime.now().add(Duration(seconds: widget._seconds));
    _notificationId = DateTime.now().millisecondsSinceEpoch.remainder(1 << 31);

    // Drives the once-per-second rebuild; the ring's own motion between
    // ticks comes from the TweenAnimationBuilder in build() below, not from
    // a long-running Ticker -- a Ticker spanning the whole countdown would
    // keep the scheduler "busy" for the rest period's full duration, which
    // is exactly what widget tests' pumpAndSettle() isn't meant to sit
    // through.
    _uiTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      // ignore: no-empty-block, avoid-empty-setstate
      if (mounted) {
        setState(() {});
      }
    });

    final gymState = ref.read(gymStateProvider);
    if (gymState.alertOnCountdownEnd) {
      _notificationScheduled = true;
      ref.read(restTimerNotificationServiceProvider).scheduleRestEnd(
            id: _notificationId,
            endTime: _endTime,
          );
    }
  }

  @override
  void dispose() {
    _uiTimer.cancel();
    // Covers skipping past the rest early: don't let a stale notification
    // fire for a countdown the user already moved on from.
    if (_notificationScheduled) {
      ref.read(restTimerNotificationServiceProvider).cancel(_notificationId);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final remaining = _endTime.difference(DateTime.now());
    final remainingSeconds = remaining.inSeconds <= 0 ? 0 : remaining.inSeconds;
    final progress = widget._seconds == 0 ? 1.0 : 1 - (remainingSeconds / widget._seconds);
    final displayTime = DateTime(2000, 1, 1, 0, 0, 0).add(Duration(seconds: remainingSeconds));
    final gymState = ref.watch(gymStateProvider);

    //  When countdown finishes, alert ONCE, and respect settings
    if (remainingSeconds == 0 && !_hasFiredLocalAlert) {
      _hasFiredLocalAlert = true;
      if (gymState.alertOnCountdownEnd) {
        // Immediate tactile feedback while the app is foregrounded; the
        // notification scheduled in initState (which also carries a channel
        // sound) is what covers backgrounded/locked devices, which this
        // alone never could.
        HapticFeedback.mediumImpact();
      }
    }

    return Column(
      children: [
        NavigationHeader(
          AppLocalizations.of(context).pause,
          widget._controller,
        ),
        Expanded(
          child: Center(
            child: SizedBox(
              width: 220,
              height: 220,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  TweenAnimationBuilder<double>(
                    tween: Tween<double>(begin: 0, end: progress),
                    duration: AppMotion.standard,
                    curve: AppMotion.standardCurve,
                    builder: (context, value, child) => SizedBox(
                      width: 220,
                      height: 220,
                      child: CircularProgressIndicator(
                        value: value,
                        strokeWidth: 10,
                        backgroundColor: wgerPrimaryColor.withValues(alpha: 0.15),
                        valueColor: const AlwaysStoppedAnimation<Color>(wgerPrimaryColor),
                      ),
                    ),
                  ),
                  Text(
                    DateFormat('m:ss').format(displayTime),
                    style: Theme.of(context).textTheme.displayLarge!.copyWith(
                          color: wgerPrimaryColor,
                        ),
                  ),
                ],
              ),
            ),
          ),
        ),
        NavigationFooter(widget._controller),
      ],
    );
  }
}
