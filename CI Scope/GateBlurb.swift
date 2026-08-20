import Foundation

/// The four descriptive strings every gate seed carries, kept together so seed
/// factories take a handful of arguments instead of a wall of them.
struct GateBlurb {
  let id: String
  let title: String
  let summary: String
  let detail: String
}
