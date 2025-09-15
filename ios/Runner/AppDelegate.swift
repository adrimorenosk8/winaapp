import UIKit
import Flutter
import UserNotifications
import FirebaseMessaging   // del plugin firebase_messaging

@main
@objc class AppDelegate: FlutterAppDelegate {

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {

    // No llamamos a FirebaseApp.configure() aquí (ya lo haces en Dart).
    // Solo configuramos el delegate y registramos APNs.
    UNUserNotificationCenter.current().delegate = self

    // Registramos APNs (la petición de permisos la haces en Dart con FirebaseMessaging.requestPermission)
    application.registerForRemoteNotifications()

    GeneratedPluginRegistrant.register(with: self)
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  // ✅ APNs token recibido → pásalo a Firebase (para que FCM pueda emitir su token)
  override func application(_ application: UIApplication,
                            didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
    // Log legible del APNs token
    let token = deviceToken.map { String(format: "%02.2hhx", $0) }.joined()
    print("✅ APNs device token: \(token)")

    // Enlazar APNs con Firebase Messaging (clave para obtener FCM token)
    Messaging.messaging().apnsToken = deviceToken

    super.application(application, didRegisterForRemoteNotificationsWithDeviceToken: deviceToken)
  }

  // ❌ Error APNs
  override func application(_ application: UIApplication,
                            didFailToRegisterForRemoteNotificationsWithError error: Error) {
    print("❌ Error al registrar APNs: \(error.localizedDescription)")
    super.application(application, didFailToRegisterForRemoteNotificationsWithError: error)
  }
}
