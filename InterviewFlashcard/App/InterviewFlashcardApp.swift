import BackgroundTasks
import SwiftUI
import UIKit
import InterviewFlashcardCore

@MainActor
final class InterviewFlashcardAppDelegate: NSObject, UIApplicationDelegate {
    let runtime: AppRuntime
    private var batteryStateObserver: NSObjectProtocol?

    override init() {
        do {
            runtime = try AppRuntime()
        } catch {
            fatalError("Unable to initialize local persistence: \(error.localizedDescription)")
        }
        super.init()
    }

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        registerBackgroundImportTask()
        configureDeveloperKeepAwake()
        return true
    }

    func applicationDidBecomeActive(_ application: UIApplication) {
        updateDeveloperKeepAwake()
    }

    func applicationWillResignActive(_ application: UIApplication) {
        UIApplication.shared.isIdleTimerDisabled = false
    }

    /// The installer marks this debug launch when the phone is attached to
    /// the development Mac. This is app-scoped and does not change the
    /// user's system Auto-Lock setting. iOS exposes external power state,
    /// but not the identity of the USB host, so unplugging is the boundary
    /// we can observe with public APIs.
    private func configureDeveloperKeepAwake() {
#if DEBUG
        guard runtime.environment.launchOptions.keepAwakeWhileConnected else {
            return
        }

        let device = UIDevice.current
        device.isBatteryMonitoringEnabled = true
        batteryStateObserver = NotificationCenter.default.addObserver(
            forName: UIDevice.batteryStateDidChangeNotification,
            object: device,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.updateDeveloperKeepAwake()
            }
        }
        updateDeveloperKeepAwake()
#endif
    }

    private func updateDeveloperKeepAwake() {
#if DEBUG
        guard runtime.environment.launchOptions.keepAwakeWhileConnected else {
            UIApplication.shared.isIdleTimerDisabled = false
            return
        }

        let state = UIDevice.current.batteryState
        UIApplication.shared.isIdleTimerDisabled = switch state {
        case .charging, .full, .unknown:
            true
        case .unplugged:
            false
        @unknown default:
            true
        }
#endif
    }

    func applicationDidEnterBackground(_ application: UIApplication) {
        scheduleBackgroundImport()
    }

    func scheduleBackgroundImport() {
        BGTaskScheduler.shared.cancel(
            taskRequestWithIdentifier: AppRuntime.backgroundImportTaskIdentifier
        )

        let request = BGProcessingTaskRequest(
            identifier: AppRuntime.backgroundImportTaskIdentifier
        )
        request.requiresNetworkConnectivity = true
        request.requiresExternalPower = false
        request.earliestBeginDate = Date(timeIntervalSinceNow: 1)

        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            // The persisted run remains recoverable when the app is opened
            // again. Scheduling is best effort because iOS owns the timing.
        }
    }

    private func registerBackgroundImportTask() {
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: AppRuntime.backgroundImportTaskIdentifier,
            using: nil
        ) { [weak self] task in
            guard let task = task as? BGProcessingTask else {
                task.setTaskCompleted(success: false)
                return
            }

            Task { @MainActor [weak self] in
                self?.handleBackgroundImport(task: task)
            }
        }
    }

    private func handleBackgroundImport(task: BGProcessingTask) {
        let work = Task { @MainActor [weak self] in
            guard let self else { return false }
            return await runtime.processPendingImports()
        }
        task.expirationHandler = { work.cancel() }

        Task { @MainActor [weak self] in
            let success = await work.value
            task.setTaskCompleted(success: success)
            if !success {
                self?.scheduleBackgroundImport()
            }
        }
    }
}

@main
struct InterviewFlashcardApp: App {
    @UIApplicationDelegateAdaptor(InterviewFlashcardAppDelegate.self)
    private var appDelegate
    @State private var didBootstrap = false

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .environment(appDelegate.runtime.environment)
                .task {
                    requestPortraitOrientation()
                    guard !didBootstrap else { return }
                    didBootstrap = true
                    appDelegate.runtime.bootstrap()
                    appDelegate.scheduleBackgroundImport()
                }
        }
        .modelContainer(appDelegate.runtime.modelContainer)
    }

    private func requestPortraitOrientation() {
        guard #available(iOS 16.0, *) else { return }

        for scene in UIApplication.shared.connectedScenes {
            guard let windowScene = scene as? UIWindowScene else { continue }
            windowScene.requestGeometryUpdate(
                .iOS(interfaceOrientations: .portrait)
            )
        }
    }
}
