extension AppDependencies {
    static func live() -> AppDependencies {
        AppDependencies(
            recorder: ScreenRecorder(),
            areaSelector: AreaSelector(),
            countdown: CountdownOverlay(),
            hud: RecordingHUD()
        )
    }
}
