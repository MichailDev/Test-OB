import Foundation

extension BacktestSnapshot {
  func decodedLeagueStats() -> [String: StoredSegmentStats] {
    guard let d = perLeagueJSON else { return [:] }
    return (try? JSONDecoder().decode([String: StoredSegmentStats].self, from: d)) ?? [:]
  }
  func decodedMarketStats() -> [String: StoredSegmentStats] {
    guard let d = perMarketJSON else { return [:] }
    return (try? JSONDecoder().decode([String: StoredSegmentStats].self, from: d)) ?? [:]
  }
  func decodedLeagueMarketStats() -> [String: StoredSegmentStats] {
    guard let d = perLeagueMarketJSON else { return [:] }
    return (try? JSONDecoder().decode([String: StoredSegmentStats].self, from: d)) ?? [:]
  }
  func decodedEVBuckets() -> [String: StoredSegmentStats] {
    guard let d = evBucketsJSON else { return [:] }
    return (try? JSONDecoder().decode([String: StoredSegmentStats].self, from: d)) ?? [:]
  }
  func decodedOddsBuckets() -> [String: StoredSegmentStats] {
    guard let d = oddsBucketsJSON else { return [:] }
    return (try? JSONDecoder().decode([String: StoredSegmentStats].self, from: d)) ?? [:]
  }
  func decodedClassification() -> [String: StoredSegmentStats] {
    guard let d = classificationJSON else { return [:] }
    return (try? JSONDecoder().decode([String: StoredSegmentStats].self, from: d)) ?? [:]
  }
  func decodedPosteriorBuckets() -> [PosteriorBucket] {
    guard let d = posteriorJSON else { return [] }
    return (try? JSONDecoder().decode([PosteriorBucket].self, from: d)) ?? []
  }
  func decodedPosteriorCornersBuckets() -> [PosteriorBucket] {
    guard let d = posteriorCornersJSON else { return [] }
    return (try? JSONDecoder().decode([PosteriorBucket].self, from: d)) ?? []
  }
  func decodedPosteriorCardsBuckets() -> [PosteriorBucket] {
    guard let d = posteriorCardsJSON else { return [] }
    return (try? JSONDecoder().decode([PosteriorBucket].self, from: d)) ?? []
  }
  func decodedModelComparison() -> [ModelComparison] {
    guard let d = modelComparisonJSON else { return [] }
    return (try? JSONDecoder().decode([ModelComparison].self, from: d)) ?? []
  }
  func decodedOOSReport() -> OOSValidationReport {
    guard let d = oosValidationJSON else { return .empty }
    return (try? JSONDecoder().decode(OOSValidationReport.self, from: d)) ?? .empty
  }
  func decodedTrainReport() -> WalkForwardDelta? {
    guard let d = trainReportJSON else { return nil }
    return try? JSONDecoder().decode(WalkForwardDelta.self, from: d)
  }
  func decodedValidationReport() -> WalkForwardDelta? {
    guard let d = validationReportJSON else { return nil }
    return try? JSONDecoder().decode(WalkForwardDelta.self, from: d)
  }
  func decodedHoldoutReport() -> WalkForwardDelta? {
    guard let d = holdoutReportJSON else { return nil }
    return try? JSONDecoder().decode(WalkForwardDelta.self, from: d)
  }
}
