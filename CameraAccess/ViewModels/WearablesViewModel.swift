/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 * All rights reserved.
 *
 * This source code is licensed under the license found in the
 * LICENSE file in the root directory of this source tree.
 */

//
// WearablesViewModel.swift
//
// Primary view model for the TurboMeta app that manages DAT SDK integration.
// Demonstrates how to listen to device availability changes using the DAT SDK's
// device stream functionality and handle permission requests.
//

import MWDATCore
import SwiftUI

#if DEBUG
import MWDATMockDevice
#endif

@MainActor
class WearablesViewModel: ObservableObject {
  @Published var devices: [DeviceIdentifier]
  @Published var hasMockDevice: Bool
  @Published var registrationState: RegistrationState
  @Published var showGettingStartedSheet: Bool = false
  @Published var showError: Bool = false
  @Published var errorMessage: String = ""

  private var registrationTask: Task<Void, Never>?
  private var deviceStreamTask: Task<Void, Never>?
  private let wearables: WearablesInterface
  private var compatibilityListenerTokens: [DeviceIdentifier: AnyListenerToken] = [:]

  init(wearables: WearablesInterface) {
    self.wearables = wearables
    self.devices = wearables.devices
    self.hasMockDevice = false
    self.registrationState = wearables.registrationState

    registrationTask = Task {
      for await registrationState in wearables.registrationStateStream() {
        print("🔵 [DEBUG] Registration state changed: \(registrationState)")
        let previousState = self.registrationState
        self.registrationState = registrationState
        if self.showGettingStartedSheet == false && registrationState == .registered && previousState == .registering {
          self.showGettingStartedSheet = true
        }
        if registrationState == .registered {
          print("🔵 [DEBUG] Device registered, setting up device stream...")
          await setupDeviceStream()
        }
      }
    }
  }

  deinit {
    registrationTask?.cancel()
    deviceStreamTask?.cancel()
  }

  private func setupDeviceStream() async {
    if let task = deviceStreamTask, !task.isCancelled {
      task.cancel()
    }

    deviceStreamTask = Task {
      for await devices in wearables.devicesStream() {
        print("🔵 [DEBUG] Devices list updated: \(devices.count) device(s) found")
        for (index, device) in devices.enumerated() {
          print("🔵 [DEBUG]   Device \(index + 1): \(device)")
        }
        self.devices = devices
        #if DEBUG
        self.hasMockDevice = !MockDeviceKit.shared.pairedDevices.isEmpty
        #endif
        // Monitor compatibility for each device
        monitorDeviceCompatibility(devices: devices)
      }
    }
  }

  private func monitorDeviceCompatibility(devices: [DeviceIdentifier]) {
    // Remove listeners for devices that are no longer present
    let deviceSet = Set(devices)
    compatibilityListenerTokens = compatibilityListenerTokens.filter { deviceSet.contains($0.key) }

    // Add listeners for new devices
    for deviceId in devices {
      guard compatibilityListenerTokens[deviceId] == nil else { continue }
      guard let device = wearables.deviceForIdentifier(deviceId) else { continue }

      // Capture device name before the closure to avoid Sendable issues
      let deviceName = device.nameOrId()
      let token = device.addCompatibilityListener { [weak self] compatibility in
        guard let self else { return }
        print("🟡 [DEBUG] Device '\(deviceName)' compatibility: \(compatibility)")
        if compatibility == .deviceUpdateRequired {
          Task { @MainActor in
            print("🔴 [DEBUG] Device '\(deviceName)' requires firmware update!")
            self.showError("Device '\(deviceName)' requires an update to work with this app")
          }
        }
      }
      compatibilityListenerTokens[deviceId] = token
    }
  }

  func connectGlasses() {
    print("🔵 [DEBUG] connectGlasses() called, current registrationState: \(registrationState)")
    guard registrationState != .registering else { 
      print("🟡 [DEBUG] Already registering, ignoring...")
      return 
    }
    do {
      print("🔵 [DEBUG] Starting registration...")
      try wearables.startRegistration()
    } catch {
      print("🔴 [DEBUG] Registration error: \(error)")
      showError(error.description)
    }
  }

  func disconnectGlasses() {
    do {
      try wearables.startUnregistration()
    } catch {
      showError(error.description)
    }
  }

  func showError(_ error: String) {
    errorMessage = error
    showError = true
  }

  func dismissError() {
    showError = false
  }
}
