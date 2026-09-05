//
//  ForecastModels.swift
//  mlx-ios-toolcall
//
//  Created by Serhat Akar on 04/09/2026.
//

import Foundation

struct TimeSeriesPoint: Identifiable, Hashable, Sendable{
    var date : Date
    var value : Double
    var id: Date {date}
}

struct ForecastPoint: Identifiable, Hashable, Sendable{
    var date : Date
    var lower : Double
    var median: Double
    var upper : Double
    var id: Date {date}

}

struct ForecastResult: Sendable{
    var seriesName:String
    var unit: String
    var history: [TimeSeriesPoint]
    var forecast: [ForecastPoint]
}

