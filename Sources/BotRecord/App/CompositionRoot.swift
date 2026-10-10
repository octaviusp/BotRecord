extension AppDependencies {
    static func live() -> AppDependencies {
        AppDependencies(
            recorder: ScreenRecorder(),
            meetingRecorder: MeetingRecorder(),
            areaSelector: AreaSelector(),
            countdown: CountdownOverlay(),
            hud: RecordingHUD()
        )
    }
}
