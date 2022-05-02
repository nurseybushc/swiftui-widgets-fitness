//
//  AppWorkoutsList.swift
//  Workout Companion
//
//  Created by Admin on 4/20/22.
//

import Foundation
import SwiftUI

struct AppWorkoutsList: View {
    @EnvironmentObject var workoutManager: WorkoutManager
    typealias DictAppWorkouts = [String: AppWorkoutModel]
    let workouts: DictAppWorkouts
    
    var body: some View {
        VStack{
            Text("\(workouts.count) workouts")
            if #available(iOS 15.0, *) {
                List{
                    ForEach(Array(workouts.keys), id: \.self) { key in
                        AppWorkoutRow(appWorkout: workouts[key]!)
                    }
                }
                .refreshable {
                    workoutManager.loadWorkoutData(force: true)
                }
            } else {
                // Fallback on earlier versions
                List{
                    ForEach(Array(workouts.keys), id: \.self) { key in
                        AppWorkoutRow(appWorkout: workouts[key]!)
                    }
                }
            }
        }
    }
}

struct AppWorkoutRow: View {
    var appWorkout: AppWorkoutModel
    
    var body: some View {
        Text("Wk \(appWorkout.id) kcal \(appWorkout.totalEeneryBurned)")
    }
}
