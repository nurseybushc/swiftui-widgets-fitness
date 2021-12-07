//
//  WorkoutManager.swift
//  Workout Companion
//
//  Created by Mario Eguiluz on 27/04/2021.
//

import Foundation
import HealthKit
import Combine
import MapKit


class WorkoutManager: NSObject, ObservableObject {

    @Published var weekWorkoutModel = WeekWorkoutModel(workouts: [])
    @Published var mapWorkoutModel: MapWorkoutModel? = nil
    @Published var recentWorkouts: [HKWorkout] = []
    @Published var allRunningWorkouts: [HKWorkout] = []

    private var healthStore: HKHealthStore?

    init(
        weekWorkoutModel: WeekWorkoutModel = WeekWorkoutModel(workouts: []),
        mapWorkoutModel: MapWorkoutModel? = nil,
        recentWorkouts: [HKWorkout] = [],
        allRunningWorkouts: [HKWorkout] = []) {
        
        self.weekWorkoutModel = weekWorkoutModel
        self.mapWorkoutModel = mapWorkoutModel
        self.recentWorkouts = recentWorkouts
        self.allRunningWorkouts = allRunningWorkouts

        if HKHealthStore.isHealthDataAvailable() {
            healthStore = HKHealthStore()
        }
    }

    func requestAuthorization(onSuccess: @escaping () -> Void, onError: @escaping (Error?) -> Void) {
        if HKHealthStore.isHealthDataAvailable() {
            let typesToRead: Set = [
                HKObjectType.workoutType(),
                HKSeriesType.workoutRoute(),
                HKQuantityType.quantityType(forIdentifier: .heartRate)!,
                HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned)!,
                HKQuantityType.quantityType(forIdentifier: .distanceWalkingRunning)!
            ]
            healthStore?.requestAuthorization(toShare: nil, read: typesToRead) { (result, error) in
                if let error = error {
                    onError(error)
                    return
                }
                guard result else {
                    onError(nil)
                    return
                }
                onSuccess()
           }
        }
    }
    
    func loadWorkoutData() {
        print("loadWorkoutData")
        latestMapWorkout()
        latestWorkoutWeekDays()
        latestWorkouts()
        getAllRunningWorkouts()
    }
    
    // ALL RUNNING WORKOUTS
    func getAllRunningWorkouts(completion: (([HKWorkout]) -> Void)? = nil){
        print("getAllRunningWorkouts begin")
        let workoutPredicate = HKQuery.predicateForWorkouts(with: .running)
        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierEndDate,
                                              ascending: true)
        let query = HKSampleQuery(sampleType: HKObjectType.workoutType(),
                                  predicate: workoutPredicate,
                                  limit: Int(HKObjectQueryNoLimit),
                                  sortDescriptors: [sortDescriptor])
          { (query, samples, error) in
           
              DispatchQueue.main.async { [self] in
                  guard let samples = samples as? [HKWorkout], error == nil else {
                      self.allRunningWorkouts = []
                      completion?([])
                      return
                  }
                  self.allRunningWorkouts = samples
                  
                  print("getAllRunningWorkouts end count: \(self.allRunningWorkouts.count)")
                  self.processRunningWorkouts(wks: samples)
                  completion?(samples)
              }
        }
        
        HKHealthStore().execute(query)
    }
    
    func getStepsForWorkout(wk: HKWorkout){
        
    }
    
    func getDistanceForWorkout(wk: HKWorkout){
        let workoutPredicate = HKQuery.predicateForObjects(from: wk)
        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierEndDate,
                                              ascending: true)
        
        guard let sampleType = HKSampleType.quantityType(forIdentifier: HKQuantityTypeIdentifier.distanceWalkingRunning) else {
            fatalError("*** This method should never fail ***")
        }
        
        //let query = HK
        let query = HKSampleQuery(sampleType: sampleType,
                                    predicate: workoutPredicate,
                                  limit: Int(HKObjectQueryNoLimit),
                                  sortDescriptors: [sortDescriptor])
          { (query, samples, error) in
           
              DispatchQueue.main.async {
                  guard let wkSamples = samples else { return }
                  if wkSamples.count > 0 {
                      print("workout \(wk.uuid) has \(wkSamples.count) samples")
                      
                      guard let currData:HKQuantitySample = wkSamples[0] as? HKQuantitySample else { return }
                      let distance = currData.quantity.doubleValue(for: HKUnit.meter())
                      print("workout \(wk.uuid) distance \(distance)")
                  }
              }
        }
        
        HKHealthStore().execute(query)
    }
    
    func getCaloriesForWorkout(wk: HKWorkout){
        let workoutPredicate = HKQuery.predicateForObjects(from: wk)
        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierEndDate,
                                              ascending: true)
                
        guard let sampleType = HKSampleType.quantityType(forIdentifier: HKQuantityTypeIdentifier.activeEnergyBurned) else {
            fatalError("*** This method should never fail ***")
        }
        
        //let query = HK
        let query = HKSampleQuery(sampleType: sampleType,
                                    predicate: workoutPredicate,
                                  limit: Int(HKObjectQueryNoLimit),
                                  sortDescriptors: [sortDescriptor])
          { (query, samples, error) in
           
              DispatchQueue.main.async {
                  guard let wkSamples = samples else { return }
                  if wkSamples.count > 0 {
                      print("workout \(wk.uuid) has \(wkSamples.count) samples")
                      
                      guard let currData:HKQuantitySample = wkSamples[0] as? HKQuantitySample else { return }
                      let calories = currData.quantity.doubleValue(for: HKUnit.largeCalorie())
                      print("workout \(wk.uuid) calories \(calories) \(HKUnit.largeCalorie())")
                  }
                
              }
        }
        
        HKHealthStore().execute(query)
    }
    
    func getHeartRateForWorkout(wk: HKWorkout){
        
    }
    
    func processRunningWorkouts(wks: [HKWorkout]){
        print("processing running workouts...")
        
        //for index in 1...5 {
        for wk in wks {
            DispatchQueue.global(qos: .background).async { [self] in
                getCaloriesForWorkout(wk: wk)
            }
            
            DispatchQueue.global(qos: .background).async { [self] in
                getDistanceForWorkout(wk: wk)
            }
        }
    }

    // LAST WEEK WORKOUTS
    func latestWorkoutWeekDays(completion: ((WeekWorkoutModel) -> Void)? = nil) {
        print("latestWorkoutWeekDays begin")
        let end = Date()
        let start = Calendar.current.date(byAdding: .day, value: -7, to: end)!
        let workoutPredicate = HKQuery.predicateForWorkouts(with: .greaterThanOrEqualTo, duration: 1)
        let datePredicate = HKQuery.predicateForSamples(withStart: start, end: end, options: [])
        let compound = NSCompoundPredicate(andPredicateWithSubpredicates:[workoutPredicate, datePredicate])
        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)

        let query = HKSampleQuery(
            sampleType: .workoutType(),
            predicate: compound,
            limit: 0,
            sortDescriptors: [sortDescriptor]) { (query, samples, error) in
            DispatchQueue.main.async {
                guard let samples = samples as? [HKWorkout], error == nil else {
                    let result = WeekWorkoutModel(workouts: [])
                    self.weekWorkoutModel = result
                    completion?(result)
                    return
                }
                let result =  WeekWorkoutModel(workouts: samples)
                print("latestWorkoutWeekDays end count: \(samples.count)")
                self.weekWorkoutModel = result
                completion?(result)
            }
          }

        healthStore?.execute(query)
    }

    // MAP WORKOUT
    func latestMapWorkout() {
        print("latestMapWorkout begin")
        let walkingPredicate = HKQuery.predicateForWorkouts(with: .walking)
        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)
        let query = HKSampleQuery(sampleType: .workoutType(), predicate: walkingPredicate, limit: 5, sortDescriptors: [sortDescriptor]) { (query, samples, error) in
            DispatchQueue.main.async {
                guard let samples = samples as? [HKWorkout], error == nil, let mapWorkout = samples.first else {
                    self.mapWorkoutModel = nil
                    return
                }
                self.publishMapWorkout(workout: mapWorkout)
            }
        }
        healthStore?.execute(query)
    }

    private func publishMapWorkout(workout: HKWorkout) {
        let workoutRouteType = HKSeriesType.workoutRoute()
        let workoutPredicate = HKQuery.predicateForObjects(from: workout)
        let workoutRoutesQuery = HKSampleQuery(sampleType: workoutRouteType, predicate: workoutPredicate, limit: HKObjectQueryNoLimit, sortDescriptors: nil) { (query, samples, error) in

            guard let routeSamples = samples as? [HKWorkoutRoute] else { return }
            var accumulator: [CLLocation] = []
            for routeSample in routeSamples {
                let locationQuery = HKWorkoutRouteQuery(route: routeSample) { (routeQuery, locations, done, error) in
                    if let locations = locations {
                        accumulator.append(contentsOf: locations)
                        if done {
                            let coordinates2D = accumulator.map { $0.coordinate }
                            let region = MKCoordinateRegion(coordinates: coordinates2D)
                            DispatchQueue.main.async {
                                self.mapWorkoutModel = MapWorkoutModel(workout: workout, region: region, coordinates: coordinates2D)
                            }
                        }
                    }
                }
                self.healthStore?.execute(locationQuery)
            }
        }
        healthStore?.execute(workoutRoutesQuery)
    }
    
    // RECENT WORKOUTS
    func latestWorkouts(completion: (([HKWorkout]) -> Void)? = nil) {
        print("latestWorkouts begin")
        let end = Date()
        let start = Calendar.current.date(byAdding: .day, value: -7, to: end)!
        let workoutPredicate = HKQuery.predicateForWorkouts(with: .greaterThanOrEqualTo, duration: 1)
        let datePredicate = HKQuery.predicateForSamples(withStart: start, end: end, options: [])
        let compound = NSCompoundPredicate(andPredicateWithSubpredicates:[workoutPredicate, datePredicate])
        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)

        let query = HKSampleQuery(
            sampleType: .workoutType(),
            predicate: compound,
            limit: 0,
            sortDescriptors: [sortDescriptor]) { (query, samples, error) in
            
                DispatchQueue.main.async {
                guard let samples = samples as? [HKWorkout], error == nil else {
                    self.recentWorkouts = []
                    completion?([])
                    return
                }
                self.recentWorkouts = samples
                print("latestWorkouts end count: \(self.recentWorkouts.count)")
                completion?(samples)
            }
          }

        healthStore?.execute(query)
    }
}
