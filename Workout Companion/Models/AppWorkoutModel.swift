//
//  AppWorkoutModel.swift
//  Workout Companion
//
//  Created by Admin on 4/16/22.
//

import Foundation

struct AppWorkoutModel: Codable {
    var id: String
    var startDate: Date
    var endDate: Date
    var duration: Double
    var mets: Double = 0.0
    var appleExerciseTime: Double = 0.0
    var steps: Double = 0.0
    var totalDistance: Double = 0.0
    var totalEeneryBurned: Double = 0.0
    
    init(id: String, startDate: Date, endDate: Date, duration: Double) {
        self.id = id
        self.startDate = startDate
        self.endDate = endDate
        self.duration = duration
    }
}
