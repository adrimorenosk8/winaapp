import UIKit
import Flutter
import FirebaseCore
import FirebaseMessaging
import UserNotifications

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    
    // 🔹 Inicializa Firebase (si no estaba ya configurado)
    if FirebaseApp.app() == nil {
      FirebaseApp.configure()
    }
    
    // 🔹 Configura notificaciones push
    UNUserNotificationCenter.current().delegate = self
    
    // Solicita permisos de notificación (alerta, badge, sonido)
    UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { granted, error in
      if let error = error {
        print("⚠️ Error solicitando permisos: \(error)")
      } else {
        print("✅ Permisos concedidos: \(granted)")
      }
    }
    
    // 🔹 Registro en APNs
    application.registerForRemoteNotifications()
    
    // 🔹 Registra plugins de Flutter
    GeneratedPluginRegistrant.register(with: self)
    
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  // MARK: - APNs Token registrado
  override func application(_ application: UIApplication,
                            didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
    Messaging.messaging().apnsToken = deviceToken
    let tokenString = deviceToken.map { String(format: "%02.2hhx", $0) }.joined()
    print("📱 APNs device token: \(tokenString)")
    super.application(application, didRegisterForRemoteNotificationsWithDeviceToken: deviceToken)
  }

  // MARK: - Error al registrar APNs
  override func application(_ application: UIApplication,
                            didFailToRegisterForRemoteNotificationsWithError error: Error) {
    print("❌ Error registrando APNs: \(error)")
    super.application(application, didFailToRegisterForRemoteNotificationsWithError: error)
  }
}
