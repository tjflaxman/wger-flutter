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

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:logging/logging.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

/// Fires a one-shot local notification (sound + vibration) when a rest-timer
/// countdown ends, so the alert reaches the user even if the app is
/// backgrounded, the screen is locked, or the app has been killed -- none of
/// which the previous foreground-only HapticFeedback/SystemSound combo could
/// do. Abstracted behind an interface so widget tests (which have no native
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

  Future<void> cancel(int id);
}

class FlutterRestTimerNotificationService implements RestTimerNotificationService {
  static const _channelId = 'rest_timer';
  static const _channelName = 'Rest timer';
  static const _channelDescription = 'Alerts when a rest-between-sets countdown ends';

  final _logger = Logger('RestTimerNotificationService');
  final _plugin = FlutterLocalNotificationsPlugin();
  bool _initialized = false;

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
      _logger.warning('Could not resolve local timezone, falling back to UTC: $e');
    }

    const androidSettings = AndroidInitializationSettings('@drawable/ic_launcher_foreground');
    const initSettings = InitializationSettings(android: androidSettings);
    await _plugin.initialize(settings: initSettings);

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
  Future<void> cancel(int id) => _plugin.cancel(id: id);
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
  Future<void> cancel(int id) async {}
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
