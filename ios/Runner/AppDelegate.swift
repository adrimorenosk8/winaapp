import UIKit
import Flutter
import UserNotifications
import FirebaseMessaging   // plugin de firebase_messaging

@UIApplicationMain
@objc class AppDelegate: FlutterAppDelegate {

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {

    // Deja que Flutter pida permisos; aquí solo fijamos el delegate y registramos APNs.
    if #available(iOS 10.0, *) {
      UNUserNotificationCenter.current().delegate = self
    }

    // ⚠️ IMPORTANTE: registra APNs (no bloquea y es seguro si aún no dieron permiso)
    application.registerForRemoteNotifications()

    GeneratedPluginRegistrant.register(with: self)
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  // ✅ APNs device token recibido: log + enlazar con FCM
  override func application(_ application: UIApplication,
                            didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
    let apnsHex = deviceToken.map { String(format: "%02.2hhx", $0) }.joined()
    print("✅ APNs device token: \(apnsHex)")

    // Enlazar explícitamente APNs → FCM (acelera la obtención del FCM token)
    Messaging.messaging().apnsToken = deviceToken

    // (Diagnóstico) intenta leer el FCM token nativo
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
