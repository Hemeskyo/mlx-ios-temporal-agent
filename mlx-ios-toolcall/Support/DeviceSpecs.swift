//
//  DeviceSpecs.swift
//  mlx-ios-toolcall
//
//  Created by Serhat Akar on 29/08/2026.
//


import Foundation

/// Device memory facts (RAM + jetsam headroom) used to recommend a safe cache size.
enum DeviceSpecs{
    /// Total device RAM (bytes).
    static var totalRAM: UInt64 { ProcessInfo.processInfo.physicalMemory }
    
    /// Bytes the app can still allocate before iOS kills it (jetsam headroom, right now).
    static var availableMemory: Int { os_proc_available_memory() }
    
    static var totalRAMGB: Double { Double(totalRAM) / 1_073_741_824 }
    static var availableMB: Int { availableMemory / (1024 * 1024) }
    
    /// Conservative recommended MLX cache limit (MB): live headroom minus a safety margin.
    static var recommendedCacheMB: Int {
        max(16, min(512, availableMB - 300))
    }
}
