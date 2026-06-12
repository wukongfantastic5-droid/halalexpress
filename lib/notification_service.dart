import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class NotificationService {
  static final FlutterLocalNotificationsPlugin plugin =
      FlutterLocalNotificationsPlugin();

  static const String channelId = 'gombak_runner_channel';

  // =========================
  // INIT
  // =========================
  static Future<void> init() async {
    print("🔔 NotificationService INIT");

    const AndroidInitializationSettings androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');

    const InitializationSettings settings =
        InitializationSettings(android: androidSettings);

    await plugin.initialize(
      settings,
      onDidReceiveNotificationResponse: (response) {
        print("🔔 CLICKED: ${response.payload}");
      },
    );

    // 🔥 CREATE CHANNEL MANUALLY (IMPORTANT FIX)
    const AndroidNotificationChannel channel = AndroidNotificationChannel(
      channelId,
      'Gombak Runner Notifications',
      description: 'Order notification channel',
      importance: Importance.max,
      playSound: true,
      enableVibration: true,
      sound: RawResourceAndroidNotificationSound('notification'),
    );

    final androidPlugin =
        plugin.resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();

    await androidPlugin?.createNotificationChannel(channel);

    print("🔔 CHANNEL CREATED");
  }

  // =========================
  // SHOW NOTIFICATION
  // =========================
  static Future<void> showOrderNotification({
    required String title,
    required String body,
    required String orderId,
  }) async {
    print("🔔 SHOW NOTIFICATION CALLED");
    print("Title: $title");
    print("Body: $body");
    print("Order ID: $orderId");

    const AndroidNotificationDetails androidDetails =
        AndroidNotificationDetails(
      channelId,
      'Gombak Runner Notifications',
      channelDescription: 'Order notifications',

      importance: Importance.max,
      priority: Priority.high,

      playSound: true,
      enableVibration: true,

      // 🔥 IMPORTANT
      sound: RawResourceAndroidNotificationSound('notification'),
    );

    const NotificationDetails details =
        NotificationDetails(android: androidDetails);

    await plugin.show(
      DateTime.now().millisecondsSinceEpoch ~/ 1000,
      title,
      body,
      details,
      payload: orderId,
    );

    print("✅ Notification SENT");
  }
}