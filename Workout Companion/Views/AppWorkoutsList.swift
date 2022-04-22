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
    
    var body: some View {
        VStack{
            Text("\(workoutManager.appWorkouts.count) workouts")
            List{
                ForEach(Array(workoutManager.appWorkouts.keys), id: \.self) { key in
                    AppWorkoutRow(appWorkout: workoutManager.appWorkouts[key]!)
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
