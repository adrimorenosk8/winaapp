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

    // NO configuramos Firebase aquí (ya lo haces en Dart con Firebase.initializeApp)
    // Solo dejamos listo el delegate y el registro de APNs.
    UNUserNotificationCenter.current().delegate = self

    // Si el usuario ya aceptó permisos desde Dart, esto registrará APNs.
    application.registerForRemoteNotifications()

    GeneratedPluginRegistrant.register(with: self)
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  // ✅ APNs token recibido → pásalo a Firebase (clave para que FCM genere su token)
  override func application(_ application: UIApplication,
                            didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
    // Log legible del token APNs (útil en depuración local/Xcode)
    let token = deviceToken.map { String(format: "%02.2hhx", $0) }.joined()
    print("✅ APNs device token: \(token)")

    // Importante: enlazar el token APNs con FCM
    Messaging.messaging().apnsToken = deviceToken

    super.application(application, didRegisterForRemoteNotificationsWithDeviceToken: deviceToken)
  }

  // ❌ Error APNs (si algo falla con el registro en Apple Push)
  override func application(_ application: UIApplication,
                            didFailToRegisterForRemoteNotificationsWithError error: Error) {
    print("❌ Error al registrar APNs: \(error.localizedDescription)")
    super.application(application, didFailToRegisterForRemoteNotificationsWithError: error)
  }
}
