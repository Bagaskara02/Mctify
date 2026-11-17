import Flutter
import UIKit
import AVFoundation

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    do {
      try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [.allowBluetooth, .allowAirPlay])
      try AVAudioSession.sharedInstance().setActive(true)
    } catch {
      print("AVAudioSession error: \(error)")
    }

    let controller: FlutterViewController = window?.rootViewController as! FlutterViewController
    let equalizerChannel = FlutterMethodChannel(name: "com.mcmusic.app/equalizer", binaryMessenger: controller.binaryMessenger)
    equalizerChannel.setMethodCallHandler { (call: FlutterMethodCall, result: @escaping FlutterResult) in
      switch call.method {
      case "setEnabled":
        let args = call.arguments as? [String: Any]
        let enabled = args?["enabled"] as? Bool ?? true
        AppDelegate.applyIosAudioProfile(enabled: enabled)
        result(true)
      case "setBands":
        let args = call.arguments as? [String: Any]
        let enabled = args?["enabled"] as? Bool ?? true
        let rawBands = args?["bands"] as? [Double] ?? []
        AppDelegate.applyIosBands(bands: rawBands, enabled: enabled)
        result(true)
      case "setBandLevel":
        result(true)
      case "setBassBoost":
        let args = call.arguments as? [String: Any]
        let strength = args?["strength"] as? Double ?? 0.0
        AppDelegate.applyIosBassBoost(strength: strength)
        result(true)
      case "setVirtualizer":
        result(true)
      case "setLoudnessGain":
        let args = call.arguments as? [String: Any]
        let gain = args?["gain"] as? Int ?? 0
        let enabled = args?["enabled"] as? Bool ?? true
        AppDelegate.applyIosLoudness(gainMb: gain, enabled: enabled)
        result(true)
      default:
        result(FlutterMethodNotImplemented)
      }
    }

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  static func applyIosAudioProfile(enabled: Bool) {
    do {
      let session = AVAudioSession.sharedInstance()
      try session.setCategory(.playback, mode: enabled ? .moviePlayback : .default, options: [.allowBluetooth, .allowAirPlay])
      try session.setActive(true)
    } catch {
      print("AVAudioSession apply profile error: \(error)")
    }
  }

  static func applyIosBassBoost(strength: Double) {
    do {
      let session = AVAudioSession.sharedInstance()
      let mode: AVAudioSession.Mode = strength > 0.05 ? .moviePlayback : .default
      try session.setMode(mode)
      try session.setActive(true)
    } catch {
      print("AVAudioSession bass boost error: \(error)")
    }
  }

  static func applyIosBands(bands: [Double], enabled: Bool) {
    if !enabled {
      applyIosAudioProfile(enabled: false)
      return
    }
    let bassLevel = bands.count > 0 ? bands[0] : 0.0
    let trebleLevel = bands.count > 4 ? bands[4] : 0.0
    do {
      let session = AVAudioSession.sharedInstance()
      if bassLevel > 1.5 {
        try session.setMode(.moviePlayback)
      } else if trebleLevel > 3.0 && bassLevel < 0.0 {
        try session.setMode(.spokenAudio)
      } else {
        try session.setMode(.default)
      }
      try session.setActive(true)
    } catch {
      print("AVAudioSession bands error: \(error)")
    }
  }

  static func applyIosLoudness(gainMb: Int, enabled: Bool) {
    if enabled && gainMb > 200 {
      do {
        let session = AVAudioSession.sharedInstance()
        try session.setMode(.moviePlayback)
        try session.setActive(true)
      } catch {}
    }
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
  }
}
