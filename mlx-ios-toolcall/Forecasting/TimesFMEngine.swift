//
//  TimesFMEngine.swift
//  mlx-ios-toolcall
//
//  Created by Serhat Akar on 04/09/2026.
//

import Foundation
import MLX
import TimesFMMLX

enum TimesFMEngineError: LocalizedError {
    case notLoaded
    case insufficientHistory
    case invalidQuantiles
    
    var errorDescription: String? {
           switch self {
           case .notLoaded:
               return "TimesFM has not been loaded."
           case .insufficientHistory:
               return "TimesFM needs at least 32 historical points."
           case .invalidQuantiles:
               return "TimesFM returned invalid quantiles."
           }
       }
   }


actor TimesFMEngine {
    private var forecaster: TimesFM3Forecaster?
    
    func load() async throws {
        guard forecaster == nil else {return}
        // bf16 halves TimesFM's resident memory (~1.3 GB → ~650 MB) for on-device use.
        forecaster = try await TimesFM3Forecaster.fromPretrained(ModelConfig(precision: .bfloat16))
    }
    
    func forecast(
          seriesName: String,
          unit: String,
          history: [TimeSeriesPoint],
          horizon: Int
      ) throws -> ForecastResult {
          guard let forecaster else {
              throw TimesFMEngineError.notLoaded
          }

          guard history.count >= 32 else {
              throw TimesFMEngineError.insufficientHistory
          }

          // 1-D context series (values only) → TimesFM zero-shot predict.
          // Returns a per-step median, plus a full row of quantiles when requested.
          let context = MLXArray(history.map { Float($0.value) })
          let output = try forecaster.predict(
              context,
              horizon: horizon,
              returnQuantiles: true
          )

          // `medians` = one value per future step. `quantiles` = those steps flattened,
          // with `quantilesPerStep` values each (TimesFM emits 9 quantiles per step).
          let medians = output.forecast.asArray(Float.self)

          guard
              let quantiles = output.quantiles?.asArray(Float.self),
              !medians.isEmpty,
              quantiles.count.isMultiple(of: medians.count)
          else {
              throw TimesFMEngineError.invalidQuantiles
          }

          // Outermost quantiles = the uncertainty band shown on the chart (≈ p10 … p90).
          let quantilesPerStep = quantiles.count / medians.count
          let lowerIndex = 0
          let upperIndex = quantilesPerStep - 1

          // The model returns no timestamps, so we re-date each step by reusing the
          // spacing between the last two history points (assumes a regular cadence).
          let cadence = history[history.count - 1].date
              .timeIntervalSince(history[history.count - 2].date)

          // Assemble dated points: (date, lower band, median, upper band) per future step.
          let forecast = medians.enumerated().map { index, median in
              let date = history.last!.date.addingTimeInterval(
                  cadence * Double(index + 1)
              )

              return ForecastPoint(
                  date: date,
                  lower: Double(quantiles[index * quantilesPerStep + lowerIndex]),
                  median: Double(median),
                  upper: Double(quantiles[index * quantilesPerStep + upperIndex])
              )
          }

          return ForecastResult(
              seriesName: seriesName,
              unit: unit,
              history: history,
              forecast: forecast
          )
      }
  }
