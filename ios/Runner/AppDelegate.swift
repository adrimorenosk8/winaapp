import UIKit
import Flutter
import UserNotifications
import FirebaseCore
import FirebaseMessaging

@main
@objc class AppDelegate: FlutterAppDelegate, UNUserNotificationCenterDelegate, MessagingDelegate {

  private func showAlert(_ title: String, message: String) {
    DispatchQueue.main.async {
      let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
      alert.addAction(UIAlertAction(title: "OK", style: .default, handler: nil))
      self.window?.rootViewController?.present(alert, animated: true, completion: nil)
    }
  }

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil
  ) -> Bool {

    // Asegura que Firebase nativo está configurado (no choca con Flutter)
    if FirebaseApp.app() == nil {
      FirebaseApp.configure()
    }

    // Delegados
    UNUserNotificationCenter.current().delegate = self
    Messaging.messaging().delegate = self

    // Solicita permiso de notificaciones y registra en APNs
    UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { granted, error in
      if let error = error {
        print("❌ requestAuthorization error: \(error)")
      }
      if granted {
        DispatchQueue.main.async {
          UIApplication.shared.registerForRemoteNotifications()
        }
      } else {
        print("❌ Notificaciones no concedidas")
      }
    }

    // (Por si acaso) registra en APNs
    application.registerForRemoteNotifications()

    GeneratedPluginRegistrant.register(with: self)
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  // APNs OK → llega deviceToken
  override func application(_ application: UIApplication,
                            didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
    let token = deviceToken.map { String(format: "%02.2hhx", $0) }.joined()
    print("✅ APNs device token: \(token)")
    // Pasa el token de APNs a FCM
    Messaging.messaging().apnsToken = deviceToken

    // Fuerza a FCM a calcular su token (si ya puede)
    Messaging.messaging().token { tok, err in
      if let err = err {
        print("⚠️ Error obteniendo FCM token en nativo: \(err)")
      } else {
        print("✅ FCM token (nativo): \(tok ?? "nil")")
      }
    }

    // Alerta visible (para comprobar que este callback sí se ejecuta)
    let short = String(token.prefix(12))
    showAlert("APNs OK", message: "Token: \(short)…")
  }

  override func application(_ application: UIApplication,
                            didFailToRegisterForRemoteNotificationsWithError error: Error) {
    print("❌ Fallo al registrar APNs: \(error.localizedDescription)")
    showAlert("APNs ERROR", message: error.localizedDescription)
  }

  // Mostrar la notificación en foreground (básico, sin iOS14 banners/list)
  func userNotificationCenter(_ center: UNUserNotificationCenter,
                              willPresent notification: UNNotification,
                              withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
    completionHandler([.alert, .sound, .badge])
  }

  // (Opcional) delegate de FCM para ver cuándo refresca el token nativo
  func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
    print("ℹ️ FCM didReceiveRegistrationToken: \(fcmToken ?? "nil")")
  }
}
