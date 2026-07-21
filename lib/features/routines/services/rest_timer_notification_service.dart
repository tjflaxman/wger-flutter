/*
 * This file is part of wger Workout Manager <https://github.com/wger-project>.
 * Copyright (c) 2026 wger Team
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

import 'dart:async';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:logging/logging.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

enum RestTimerActionType { add15, skip }

/// A +15s/skip tap on the live countdown notification. [slotUuid] comes back
/// as the notification's payload, since the service itself has no notion of
/// exercise slots -- routing the action to gym state is the caller's job.
class RestTimerAction {
  final String slotUuid;
  final RestTimerActionType type;

  const RestTimerAction(this.slotUuid, this.type);
}

/// Fires a one-shot local notification (sound + vibration) when a rest-timer
/// countdown ends, so the alert reaches the user even if the app is
/// backgrounded, the screen is locked, or the app has been killed -- none of
/// which the previous foreground-only HapticFeedback/SystemSound combo could
/// do. Also shows a live, lock-screen-visible countdown while resting
/// (Android's Chronometer notification style), with +15s/skip actions.
/// Abstracted behind an interface so widget tests (which have no native
/// plugin channels available) can supply a no-op fake instead of hitting the
/// real plugin.
abstract class RestTimerNotificationService {
  Future<void> init();

  /// Requests the runtime POST_NOTIFICATIONS permission (Android 13+).
  /// Returns whether the permission is granted.
  Future<bool> requestPermission();

  /// Schedules a single alert to fire at [endTime]. [id] identifies this
  /// countdown so a later [cancel] (e.g. the user skips the rest early)
  /// targets the right notification.
  Future<void> scheduleRestEnd({required int id, required DateTime endTime});

  /// Shows a live-updating countdown notification (no sound/vibration of its
  /// own -- that's what [scheduleRestEnd] is for) with +15s/skip actions,
  /// visible on the lock screen while [slotUuid]'s rest period is active.
  /// Uses the same [id] as the paired [scheduleRestEnd] call so the eventual
  /// zero-alert naturally replaces it, and a single [cancel] removes both.
  Future<void> showLiveCountdown({
    required int id,
    required String slotUuid,
    required DateTime endTime,
  });

  Future<void> cancel(int id);

  /// Fires when the user taps +15s/skip on a live countdown notification
  /// while the app is running in the foreground or background (but not
  /// fully killed -- see onDidReceiveBackgroundNotificationResponse for what
  /// that would additionally need, deliberately not implemented yet).
  Stream<RestTimerAction> get actions;

  /// Runs through permission checks and an immediate + a scheduled test
  /// notification, returning a human-readable report. Exists because there's
  /// no log access to a sideloaded device -- this turns the phone itself
  /// into the diagnostic.
  Future<String> diagnose();
}

class FlutterRestTimerNotificationService implements RestTimerNotificationService {
  static const _channelId = 'rest_timer';
  static const _channelName = 'Rest timer';
  static const _channelDescription = 'Alerts when a rest-between-sets countdown ends';

  // Separate from the alert channel above because Android locks a channel's
  // importance/sound in at creation time and never lets a single
  // notification override it -- the live countdown needs to be quiet when it
  // first appears (importance/sound belong to the zero-alert, not to
  // starting a rest period), which isn't possible on the same channel.
  //
  // "_v2" because channels are immutable once created on a device: the
  // first version used Importance.low, which (confirmed via
  // getActiveNotifications() -- the OS really was holding the notification)
  // suppresses the status bar icon and can bury it behind a "silent
  // notifications" collapse in the shade, exactly what was reported as "no
  // lockscreen/status bar countdown". Bumping this file's Importance value
  // alone wouldn't have retroactively changed an already-created channel on
  // a device that already ran an earlier build -- same lesson as the
  // scheduled-notification-receiver fix in Phase 1. A new channel id forces
  // a fresh one to be created with the corrected importance instead.
  static const _ongoingChannelId = 'rest_timer_ongoing_v2';
  static const _ongoingChannelName = 'Rest timer (in progress)';
  static const _ongoingChannelDescription = 'Live countdown while resting between sets';

  static const _addFifteenActionId = 'rest_timer_add15';
  static const _skipActionId = 'rest_timer_skip';

  final _logger = Logger('RestTimerNotificationService');
  final _plugin = FlutterLocalNotificationsPlugin();
  final _actionsController = StreamController<RestTimerAction>.broadcast();
  bool _initialized = false;
  String? _timezoneError;

  @override
  Stream<RestTimerAction> get actions => _actionsController.stream;

  void _onNotificationResponse(NotificationResponse response) {
    final slotUuid = response.payload;
    if (slotUuid == null || slotUuid.isEmpty) {
      return;
    }
    if (response.actionId == _addFifteenActionId) {
      _actionsController.add(RestTimerAction(slotUuid, RestTimerActionType.add15));
    } else if (response.actionId == _skipActionId) {
      _actionsController.add(RestTimerAction(slotUuid, RestTimerActionType.skip));
    }
  }

  @override
  Future<void> init() async {
    if (_initialized) {
      return;
    }

    tz_data.initializeTimeZones();
    try {
      final timezone = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(timezone.identifier));
    } catch (e) {
      _timezoneError = e.toString();
      _logger.warning('Could not resolve local timezone, falling back to UTC: $e');
    }

    const androidSettings = AndroidInitializationSettings('@drawable/ic_launcher_foreground');
    const initSettings = InitializationSettings(android: androidSettings);
    // Foreground/backgrounded (not fully killed) action taps only -- see the
    // interface doc on `actions` for why a killed-app entry point is out of
    // scope for now.
    await _plugin.initialize(
      settings: initSettings,
      onDidReceiveNotificationResponse: _onNotificationResponse,
    );

    // Explicit rather than relying on implicit on-demand creation: this
    // notification is delivered later via a system alarm broadcast, not
    // directly through a running instance of the app, so the channel needs
    // to already exist with the right importance/sound/vibration settings
    // by the time that broadcast fires.
    await _android?.createNotificationChannel(
      const AndroidNotificationChannel(
        _channelId,
        _channelName,
        description: _channelDescription,
        importance: Importance.max,
        playSound: true,
        enableVibration: true,
      ),
    );
    await _android?.createNotificationChannel(
      const AndroidNotificationChannel(
        _ongoingChannelId,
        _ongoingChannelName,
        description: _ongoingChannelDescription,
        importance: Importance.defaultImportance,
        playSound: false,
        enableVibration: false,
      ),
    );

    _initialized = true;
  }

  AndroidFlutterLocalNotificationsPlugin? get _android =>
      _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();

  @override
  Future<bool> requestPermission() async {
    final notificationsGranted = await _android?.requestNotificationsPermission() ?? false;

    // Separate from POST_NOTIFICATIONS: without this, Android silently
    // downgrades scheduling to "inexact", which it's free to delay by
    // several minutes once the screen is off -- exactly the case this
    // timer needs to be reliable for. There's no in-app prompt for this;
    // requestExactAlarmsPermission() hands off to the system's "Alarms &
    // reminders" settings screen for the user to grant it.
    final canScheduleExact = await _android?.canScheduleExactNotifications() ?? false;
    if (!canScheduleExact) {
      await _android?.requestExactAlarmsPermission();
    }

    return notificationsGranted;
  }

  @override
  Future<void> scheduleRestEnd({required int id, required DateTime endTime}) async {
    if (!_initialized) {
      _logger.warning('scheduleRestEnd called before init(), skipping');
      return;
    }

    const androidDetails = AndroidNotificationDetails(
      _channelId,
      _channelName,
      channelDescription: _channelDescription,
      importance: Importance.max,
      priority: Priority.high,
      playSound: true,
      enableVibration: true,
    );
    const details = NotificationDetails(android: androidDetails);

    final scheduledDate = tz.TZDateTime.from(endTime, tz.local);

    // Checked rather than try/catch around exactAllowWhileIdle: the plugin
    // doesn't reliably throw when exact-alarm permission is missing, it can
    // just silently schedule an inexact alarm under the hood instead.
    final canScheduleExact = await _android?.canScheduleExactNotifications() ?? false;
    final mode = canScheduleExact
        ? AndroidScheduleMode.exactAllowWhileIdle
        : AndroidScheduleMode.inexactAllowWhileIdle;

    await _plugin.zonedSchedule(
      id: id,
      title: 'Rest over',
      body: 'Time for your next set',
      scheduledDate: scheduledDate,
      notificationDetails: details,
      androidScheduleMode: mode,
    );
  }

  @override
  Future<void> showLiveCountdown({
    required int id,
    required String slotUuid,
    required DateTime endTime,
  }) async {
    if (!_initialized) {
      _logger.warning('showLiveCountdown called before init(), skipping');
      return;
    }

    final androidDetails = AndroidNotificationDetails(
      _ongoingChannelId,
      _ongoingChannelName,
      channelDescription: _ongoingChannelDescription,
      ongoing: true,
      autoCancel: false,
      onlyAlertOnce: true,
      usesChronometer: true,
      chronometerCountDown: true,
      showWhen: true,
      when: endTime.millisecondsSinceEpoch,
      actions: const [
        // Re-posted with a new `when:` right after handling the tap (see
        // ActiveWorkoutScreen's action-stream listener), so keep this
        // instance alive rather than let the OS auto-dismiss it first.
        AndroidNotificationAction(_addFifteenActionId, '+15s', cancelNotification: false),
        AndroidNotificationAction(_skipActionId, 'Skip'),
      ],
    );
    final details = NotificationDetails(android: androidDetails);

    // Same id as scheduleRestEnd()'s call for this slot: when that alarm
    // fires, its notification (different channel, actually alerts) replaces
    // this one outright, so there's nothing separate to clean up at zero --
    // only cancel() for an early skip.
    await _plugin.show(
      id: id,
      title: 'Resting',
      notificationDetails: details,
      payload: slotUuid,
    );
  }

  @override
  Future<void> cancel(int id) => _plugin.cancel(id: id);

  @override
  Future<String> diagnose() async {
    final buffer = StringBuffer();
    buffer.writeln('initialized: $_initialized');
    buffer.writeln('tz.local: ${tz.local.name}');
    buffer.writeln('timezoneError: $_timezoneError');

    final notificationsEnabled = await _android?.areNotificationsEnabled();
    buffer.writeln('areNotificationsEnabled: $notificationsEnabled');

    final canScheduleExact = await _android?.canScheduleExactNotifications();
    buffer.writeln('canScheduleExactNotifications: $canScheduleExact');

    final now = DateTime.now();
    final wantedEnd = now.add(const Duration(seconds: 10));
    final scheduledAsTz = tz.TZDateTime.from(wantedEnd, tz.local);
    buffer.writeln('now: $now');
    buffer.writeln('wanted end: $wantedEnd');
    buffer.writeln('as TZDateTime: $scheduledAsTz');
    buffer.writeln(
      'delta from now (ms): ${scheduledAsTz.millisecondsSinceEpoch - now.millisecondsSinceEpoch}',
    );
    buffer.writeln('scheduledAsTz.isAfter(now): ${scheduledAsTz.isAfter(now)}');

    const androidDetails = AndroidNotificationDetails(
      _channelId,
      _channelName,
      channelDescription: _channelDescription,
      importance: Importance.max,
      priority: Priority.high,
      playSound: true,
      enableVibration: true,
    );

    try {
      await _plugin.show(
        id: 999999,
        title: 'Immediate test',
        body: 'If you see this, basic delivery works',
        notificationDetails: const NotificationDetails(android: androidDetails),
      );
      buffer.writeln('show(): OK -- check the notification tray now');
    } catch (e) {
      buffer.writeln('show(): THREW: $e');
    }

    try {
      await scheduleRestEnd(id: 999998, endTime: DateTime.now().add(const Duration(seconds: 10)));
      buffer.writeln('scheduleRestEnd(+10s): OK -- wait 10s and check the tray');
    } catch (e) {
      buffer.writeln('scheduleRestEnd(+10s): THREW: $e');
    }

    try {
      final pending = await _plugin.pendingNotificationRequests();
      buffer.writeln(
        'pendingNotificationRequests: ${pending.map((p) => p.id).toList()} '
        '(999998 present = actually registered with the OS)',
      );
    } catch (e) {
      buffer.writeln('pendingNotificationRequests: THREW: $e');
    }

    try {
      await showLiveCountdown(
        id: 999997,
        slotUuid: 'diagnose-fake-slot',
        endTime: DateTime.now().add(const Duration(minutes: 2)),
      );
      buffer.writeln(
        'showLiveCountdown(): OK -- check the tray for an ongoing "Resting" '
        'notification (may need to expand the "silent"/collapsed section)',
      );
    } catch (e) {
      buffer.writeln('showLiveCountdown(): THREW: $e');
    }

    try {
      final active = await _plugin.getActiveNotifications();
      buffer.writeln(
        'active notifications: ${active.map((n) => '${n.id}(chan:${n.channelId})').toList()} '
        '(999997 present = the OS is actually holding it, not just accepted the call)',
      );
    } catch (e) {
      buffer.writeln('getActiveNotifications(): THREW: $e');
    }

    return buffer.toString();
  }
}

/// Used in widget tests, where no native plugin channels are available.
class NoopRestTimerNotificationService implements RestTimerNotificationService {
  const NoopRestTimerNotificationService();

  @override
  Future<void> init() async {}

  @override
  Future<bool> requestPermission() async => false;

  @override
  Future<void> scheduleRestEnd({required int id, required DateTime endTime}) async {}

  @override
  Future<void> showLiveCountdown({
    required int id,
    required String slotUuid,
    required DateTime endTime,
  }) async {}

  @override
  Future<void> cancel(int id) async {}

  @override
  Stream<RestTimerAction> get actions => const Stream.empty();

  @override
  Future<String> diagnose() async => 'No-op service (test environment)';
}

final restTimerNotificationServiceProvider = Provider<RestTimerNotificationService>((ref) {
  return FlutterRestTimerNotificationService();
});

/// Set once per gym-mode entry after requesting the notification permission,
/// so GymModeOptions can show a hint if it was denied. Null means "not asked
/// yet this session".
class RestTimerPermissionNotifier extends Notifier<bool?> {
  @override
  bool? build() => null;

  void set(bool granted) => state = granted;
}

final restTimerPermissionGrantedProvider =
    NotifierProvider<RestTimerPermissionNotifier, bool?>(RestTimerPermissionNotifier.new);
