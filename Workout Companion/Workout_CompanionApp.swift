//
//  Workout_CompanionApp.swift
//  Workout Companion
//
//  Created by Mario Eguiluz on 26/04/2021.
//

import SwiftUI

@main
struct Workout_CompanionApp: App {
    
    @State private var showingAlert = false
    @State private var errorMesage = ""
    
    @StateObject var workoutService = WorkoutService()
    
    var body: some Scene {
        WindowGroup {
            NavigationView {
                AppWorkoutsListNew()
                    .environmentObject(workoutService)
            }
            .alert(isPresented: $showingAlert) {
                Alert(title: Text("Something went wrong..."), message: Text(errorMesage), dismissButton: .default(Text("Ok")))
            }
            
            .task {
                workoutService.requestAuthorization(onSuccess:
                { Task {
                    try? await workoutService.fetchWorkouts(force: true)
                }}, onError: {
                    error in
                    if let error = error {
                        errorMesage = error.localizedDescription
                    }
                    showingAlert = true
                })
            }
        }
    }
}
