import os

/// Shared logger for the capture engine; failures that are recovered from are recorded here, never swallowed.
let captureLog = Logger(subsystem: AppPaths.identifier, category: "capture")
