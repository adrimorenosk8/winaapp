import UIKit
import Flutter
import FirebaseMessaging   // solo Messaging; FirebaseApp se configura en Dart

@UIApplicationMain
@objc class AppDelegate: FlutterAppDelegate {

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {

    // No pedimos permisos aquí (lo haces en Dart). Solo:
    // 1) fijamos el delegate heredado de FlutterAppDelegate
    UNUserNotificationCenter.current().delegate = self

    // 2) registramos en APNs (si el usuario ya aceptó, iOS devolverá el deviceToken)
    application.registerForRemoteNotifications()

    GeneratedPluginRegistrant.register(with: self)
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  // ✅ iOS nos da deviceToken → pásalo a Firebase Messaging
  override func application(_ application: UIApplication,
                            didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
    let apnsHex = deviceToken.map { String(format: "%02.2hhx", $0) }.joined()
    print("✅ APNs device token: \(apnsHex)")

    // Clave: enlazar APNs→FCM
    Messaging.messaging().apnsToken = deviceToken

    // Log nativo del FCM por si ya está disponible
    Messaging.messaging().token { fcm, err in
      if let err = err {
        print("⚠️ FCM token (native) error: \(err)")
      } else {
        print("✅ FCM token (native): \(fcm ?? "nil")")
      }
    }

    super.application(application, didRegisterForRemoteNotificationsWithDeviceToken: deviceToken)
  }

  override func application(_ application: UIApplication,
                            didFailToRegisterForRemoteNotificationsWithError error: Error) {
    print("❌ APNs register error: \(error.localizedDescription)")
    super.application(application, didFailToRegisterForRemoteNotificationsWithError: error)
  }
}
