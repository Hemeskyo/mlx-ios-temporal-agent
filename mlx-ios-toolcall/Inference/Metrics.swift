//
//  Metrics.swift
//  mlx-ios-toolcall
//
//  Created by Serhat Akar on 29/08/2026.
//

import Foundation

/// Performance numbers captured from one generation run.
struct Metrics {
    let promptTokens: Int
    let generationTokens: Int
    let prefillTokensPerSecond: Double
    let decodeTokensPerSecond: Double
    let promptTime: Double
    let generateTime: Double
}


