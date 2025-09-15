import UIKit
import Flutter
import UserNotifications
import FirebaseMessaging   // viene con el plugin firebase_messaging

@main
@objc class AppDelegate: FlutterAppDelegate, UNUserNotificationCenterDelegate {

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {

    // Pedir permisos de notificación y registrar APNs
    UNUserNotificationCenter.current().delegate = self
    UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { granted, error in
      if let error = error {
        print("❌ Error pidiendo permisos notificaciones: \(error)")
      }
      if granted {
        DispatchQueue.main.async {
          UIApplication.shared.registerForRemoteNotifications()
        }
      } else {
        print("ℹ️ Permisos de notificación NO concedidos (el usuario puede activarlos luego)")
      }
    }

    // Registrar de todas formas (si ya estaban concedidos no hace daño)
    application.registerForRemoteNotifications()

    GeneratedPluginRegistrant.register(with: self)
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  // ✅ APNs token recibido → pásalo a Firebase Messaging
  override func application(_ application: UIApplication,
                            didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
    // Log humano del token APNs
    let tokenParts = deviceToken.map { String(format: "%02.2hhx", $0) }
    let token = tokenParts.joined()
    print("✅ APNs device token: \(token)")

    // MUY IMPORTANTE: asociar APNs con FCM
    Messaging.messaging().apnsToken = deviceToken
  }

  // ❌ Fallo al registrar APNs
  override func application(_ application: UIApplication,
                            didFailToRegisterForRemoteNotificationsWithError error: Error) {
    print("❌ Error al registrar APNs: \(error.localizedDescription)")
  }

  // Mostrar notificaciones mientras la app está en foreground (iOS 10+)
  @available(iOS 10.0, *)
  func userNotificationCenter(_ center: UNUserNotificationCenter,
                              willPresent notification: UNNotification,
                              withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
    completionHandler([.banner, .list, .sound, .badge])
  }
}
