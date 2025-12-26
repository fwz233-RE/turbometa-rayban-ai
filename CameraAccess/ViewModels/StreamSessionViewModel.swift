/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 * All rights reserved.
 *
 * This source code is licensed under the license found in the
 * LICENSE file in the root directory of this source tree.
 */

//
// StreamSessionViewModel.swift
//
// Core view model demonstrating video streaming from Meta wearable devices using the DAT SDK.
// This class showcases the key streaming patterns: device selection, session management,
// video frame handling, photo capture, and error handling.
//

import MWDATCamera
import MWDATCore
import SwiftUI

enum StreamingStatus {
  case streaming
  case waiting
  case stopped
}

@MainActor
class StreamSessionViewModel: ObservableObject {
  @Published var currentVideoFrame: UIImage?
  @Published var hasReceivedFirstFrame: Bool = false
  @Published var streamingStatus: StreamingStatus = .stopped
  @Published var showError: Bool = false
  @Published var errorMessage: String = ""
  @Published var hasActiveDevice: Bool = false

  var isStreaming: Bool {
    streamingStatus != .stopped
  }

  // Timer properties
  @Published var activeTimeLimit: StreamTimeLimit = .noLimit
  @Published var remainingTime: TimeInterval = 0

  // Photo capture properties
  @Published var capturedPhoto: UIImage?
  @Published var showPhotoPreview: Bool = false
  @Published var showVisionRecognition: Bool = false
  @Published var showOmniRealtime: Bool = false

  private var timerTask: Task<Void, Never>?
  // The core DAT SDK StreamSession - handles all streaming operations
  private var streamSession: StreamSession
  
  // Retry mechanism for internalError
  private var retryCount = 0
  private let maxRetries = 3
  private var shouldAutoRetry = false
  // Listener tokens are used to manage DAT SDK event subscriptions
  private var stateListenerToken: AnyListenerToken?
  private var videoFrameListenerToken: AnyListenerToken?
  private var errorListenerToken: AnyListenerToken?
  private var photoDataListenerToken: AnyListenerToken?
  private let wearables: WearablesInterface
  private let deviceSelector: AutoDeviceSelector
  private var deviceMonitorTask: Task<Void, Never>?

  init(wearables: WearablesInterface) {
    self.wearables = wearables
    // Let the SDK auto-select from available devices
    self.deviceSelector = AutoDeviceSelector(wearables: wearables)
    // 使用 raw 编码 (SDK 默认支持)
    // 尝试降低参数以减少负载
    let config = StreamSessionConfig(
      videoCodec: VideoCodec.raw,
      resolution: StreamingResolution.low,
      frameRate: 15)  // 降低帧率尝试解决问题
    print("🔵 [DEBUG] StreamSession config: codec=raw, resolution=low, frameRate=15")
    streamSession = StreamSession(streamSessionConfig: config, deviceSelector: deviceSelector)

    // Monitor device availability
    deviceMonitorTask = Task { @MainActor in
      for await device in deviceSelector.activeDeviceStream() {
        self.hasActiveDevice = device != nil
        print("🔵 [DEBUG] Device availability changed: hasActiveDevice = \(device != nil), device = \(String(describing: device))")
      }
    }

    // Subscribe to session state changes using the DAT SDK listener pattern
    // State changes tell us when streaming starts, stops, or encounters issues
    stateListenerToken = streamSession.statePublisher.listen { [weak self] state in
      Task { @MainActor [weak self] in
        print("🟡 [DEBUG] Session state changed: \(state)")
        self?.updateStatusFromState(state)
      }
    }

    // Subscribe to video frames from the device camera
    // Each VideoFrame contains the raw camera data that we convert to UIImage
    var frameCount = 0
    videoFrameListenerToken = streamSession.videoFramePublisher.listen { [weak self] videoFrame in
      Task { @MainActor [weak self] in
        guard let self else { return }
        
        frameCount += 1
        // 每 30 帧打印一次，避免日志过多
        if frameCount % 30 == 1 {
          print("🟢 [DEBUG] Received video frame #\(frameCount), timestamp: \(Date())")
        }

        if let image = videoFrame.makeUIImage() {
          self.currentVideoFrame = image
          if !self.hasReceivedFirstFrame {
            print("🟢 [DEBUG] ✅ First frame received! Image size: \(image.size)")
            self.hasReceivedFirstFrame = true
          }
        } else {
          print("🔴 [DEBUG] ❌ videoFrame.makeUIImage() returned nil for frame #\(frameCount)")
        }
      }
    }

    // Subscribe to streaming errors
    // Errors include device disconnection, streaming failures, etc.
    errorListenerToken = streamSession.errorPublisher.listen { [weak self] error in
      Task { @MainActor [weak self] in
        guard let self else { return }
        print("🔴 [DEBUG] ❌ Stream error received: \(error)")
        
        // Check if we should auto-retry for internalError
        if case .internalError = error, self.shouldAutoRetry && self.retryCount < self.maxRetries {
          self.retryCount += 1
          print("🔄 [DEBUG] internalError detected, auto-retrying... (attempt \(self.retryCount)/\(self.maxRetries))")
          
          // Wait a bit before retrying
          try? await Task.sleep(nanoseconds: 1_500_000_000) // 1.5 seconds
          
          // Retry starting the session
          await self.streamSession.stop()
          print("🔄 [DEBUG] Retrying streamSession.start()...")
          await self.streamSession.start()
          return
        }
        
        // If max retries exceeded or other error, show to user
        self.shouldAutoRetry = false
        self.retryCount = 0
        
        let newErrorMessage = formatStreamingError(error)
        if newErrorMessage != self.errorMessage {
          print("🔴 [DEBUG] Showing error to user: \(newErrorMessage)")
          showError(newErrorMessage)
        }
      }
    }

    print("🔵 [DEBUG] Initial session state: \(streamSession.state)")
    updateStatusFromState(streamSession.state)

    // Subscribe to photo capture events
    // PhotoData contains the captured image in the requested format (JPEG/HEIC)
    photoDataListenerToken = streamSession.photoDataPublisher.listen { [weak self] photoData in
      Task { @MainActor [weak self] in
        guard let self else { return }
        if let uiImage = UIImage(data: photoData.data) {
          self.capturedPhoto = uiImage
          self.showPhotoPreview = true
        }
      }
    }
  }

  func handleStartStreaming() async {
    print("🔵 [DEBUG] handleStartStreaming() called")
    let permission = Permission.camera
    do {
      let status = try await wearables.checkPermissionStatus(permission)
      print("🔵 [DEBUG] Camera permission status: \(status)")
      if status == .granted {
        print("🔵 [DEBUG] Permission already granted, starting session...")
        await startSession()
        return
      }
      print("🔵 [DEBUG] Requesting camera permission...")
      let requestStatus = try await wearables.requestPermission(permission)
      print("🔵 [DEBUG] Permission request result: \(requestStatus)")
      if requestStatus == .granted {
        await startSession()
        return
      }
      print("🔴 [DEBUG] Permission denied by user")
      showError("Permission denied")
    } catch {
      print("🔴 [DEBUG] Permission error: \(error)")
      showError("Permission error: \(error.description)")
    }
  }

  func startSession() async {
    print("🔵 [DEBUG] startSession() called")
    // Reset to unlimited time when starting a new stream
    activeTimeLimit = .noLimit
    remainingTime = 0
    stopTimer()
    
    // Enable auto-retry for internalError
    retryCount = 0
    shouldAutoRetry = true

    print("🔵 [DEBUG] Calling streamSession.start()...")
    await streamSession.start()
    print("🔵 [DEBUG] streamSession.start() completed, current state: \(streamSession.state)")
  }

  private func showError(_ message: String) {
    errorMessage = message
    showError = true
  }

  func stopSession() async {
    shouldAutoRetry = false  // Disable auto-retry when stopping
    stopTimer()
    await streamSession.stop()
  }

  func dismissError() {
    showError = false
    errorMessage = ""
  }

  func setTimeLimit(_ limit: StreamTimeLimit) {
    activeTimeLimit = limit
    remainingTime = limit.durationInSeconds ?? 0

    if limit.isTimeLimited {
      startTimer()
    } else {
      stopTimer()
    }
  }

  func capturePhoto() {
    streamSession.capturePhoto(format: .jpeg)
  }

  func dismissPhotoPreview() {
    showPhotoPreview = false
    capturedPhoto = nil
  }

  private func startTimer() {
    stopTimer()
    timerTask = Task { @MainActor [weak self] in
      while let self, remainingTime > 0 {
        try? await Task.sleep(nanoseconds: NSEC_PER_SEC)
        guard !Task.isCancelled else { break }
        remainingTime -= 1
      }
      if let self, !Task.isCancelled {
        await stopSession()
      }
    }
  }

  private func stopTimer() {
    timerTask?.cancel()
    timerTask = nil
  }

  private func updateStatusFromState(_ state: StreamSessionState) {
    print("🟡 [DEBUG] updateStatusFromState: \(state) -> streamingStatus will be updated")
    switch state {
    case .stopped:
      print("🟡 [DEBUG] State: STOPPED - clearing video frame")
      currentVideoFrame = nil
      streamingStatus = .stopped
    case .waitingForDevice, .starting, .stopping, .paused:
      print("🟡 [DEBUG] State: WAITING (\(state))")
      streamingStatus = .waiting
    case .streaming:
      print("🟡 [DEBUG] State: STREAMING ✅")
      streamingStatus = .streaming
    }
  }

  private func formatStreamingError(_ error: StreamSessionError) -> String {
    switch error {
    case .internalError:
      return "An internal error occurred. Please try again."
    case .deviceNotFound:
      return "Device not found. Please ensure your device is connected."
    case .deviceNotConnected:
      return "Device not connected. Please check your connection and try again."
    case .timeout:
      return "The operation timed out. Please try again."
    case .videoStreamingError:
      return "Video streaming failed. Please try again."
    case .audioStreamingError:
      return "Audio streaming failed. Please try again."
    case .permissionDenied:
      return "Camera permission denied. Please grant permission in Settings."
    @unknown default:
      return "An unknown streaming error occurred."
    }
  }
}
