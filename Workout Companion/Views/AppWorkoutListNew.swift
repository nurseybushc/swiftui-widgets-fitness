//
//  AppWorkoutListNew.swift
//  Workout Companion
//
//  Created by Admin on 4/29/22.
//

import Foundation
import SwiftUI

struct AppWorkoutsListNew: View {
    @EnvironmentObject var workoutService: WorkoutService
    
    var body: some View {
        VStack{
            Text("\(workoutService.appWorkouts.count) workouts")
            List{
                ForEach(Array(workoutService.appWorkouts.keys), id: \.self) { key in
                    AppWorkoutRowNew(appWorkout: workoutService.appWorkouts[key]!)
                }
            }
            .refreshable {
              try? await workoutService.fetchWorkouts(force: true)
            }
        }
    }
}

struct AppWorkoutRowNew: View {
    var appWorkout: AppWorkoutModel
    
    var body: some View {
        Text("Wk \(appWorkout.id) kcal \(appWorkout.totalEeneryBurned)")
    }
}
