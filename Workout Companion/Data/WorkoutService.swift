//
//  WorkoutManagerNew.swift
//  Workout Companion
//
//  Created by Admin on 4/29/22.
//

import Foundation
import HealthKit

private actor WorkoutServiceStore {
    typealias DictAppWorkouts = [String: AppWorkoutModel]
    private var appWorkouts : DictAppWorkouts = [:]
    private var hkWorkouts : [String: HKWorkout] = [:]
    private let batchCount = 10
    
    func loadFromFile() async -> DictAppWorkouts {
        print("loadFromFile")
        do {
            let documentDirectory = try FileManager.default.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: false)
            let fileUrl = documentDirectory.appendingPathComponent("appWorkouts.json")
            let data = try Data(contentsOf: fileUrl)
            
            let decodedResponse = try? JSONDecoder().decode(DictAppWorkouts.self, from: data)
            appWorkouts = decodedResponse!
            return appWorkouts
            
        } catch {
            print("error:\(error)")
            return [:]
        }
    }
    
    func loadFromHealthKit(for healthStore: HKHealthStore) async -> DictAppWorkouts {
        print("loadFromHealthKit")
        let start = DispatchTime.now()
        
        let workoutPredicate = HKQuery.predicateForWorkouts(with: .running)
        let predicate = HKSamplePredicate.workout(workoutPredicate)
        
        let query = HKSampleQueryDescriptor(
            predicates:[predicate],
            sortDescriptors: [SortDescriptor(\.endDate, order: .reverse)],
            limit: Int(HKObjectQueryNoLimit))
        
        do {
            let wks = try await query.result(for: healthStore)
            
            print("loadFromHealthkit await done \(wks.count)")
            
            for wk in wks {
                appWorkouts[wk.uuid.uuidString] = AppWorkoutModel(id:wk.uuid.uuidString, startDate: wk.startDate, endDate: wk.endDate, duration: wk.duration)
                hkWorkouts[wk.uuid.uuidString] = wk
                
                if let metadata = wk.metadata {
                    if let avgMets = metadata[HKMetadataKeyAverageMETs] {
                        if let avgMetsQuant = avgMets as? HKQuantity {
                            let mets = avgMetsQuant.doubleValue(for: HKUnit.kilocalorie().unitDivided(by: HKUnit.gramUnit(with: .kilo).unitMultiplied(by: HKUnit.hour())))
                            
                            appWorkouts[wk.uuid.uuidString]?.mets = mets
                        }
                    }
                }
                
                //remove
                async let calories = getCaloriesForWorkoutSumAsync(for: healthStore, wk: wk)
                async let steps = getStepsForWorkoutSumAsync(for: healthStore, wk: wk)
                async let distance = getDistanceForWorkoutSumAsync(for: healthStore, wk: wk)
                async let appleExerciseTime = getAppleExeciseTimeForWorkoutSumAsync(for: healthStore, wk: wk)
                
                var resultCount = 0.0
                var result = try await calories
                if let sum = result?.sumQuantity() {
                    resultCount = sum.doubleValue(for: HKUnit.kilocalorie())
                }
                appWorkouts[wk.uuid.uuidString]?.totalEeneryBurned = resultCount
                
                resultCount = 0.0
                result = try await steps
                if let sum = result?.sumQuantity() {
                    resultCount = sum.doubleValue(for: HKUnit.count())
                }
                appWorkouts[wk.uuid.uuidString]?.steps = resultCount

                resultCount = 0.0
                result = try await distance
                if let sum = result?.sumQuantity() {
                    resultCount = sum.doubleValue(for: HKUnit.mile())
                }
                appWorkouts[wk.uuid.uuidString]?.totalDistance = resultCount
                
                resultCount = 0.0
                result = try await appleExerciseTime
                if let sum = result?.sumQuantity() {
                    resultCount = sum.doubleValue(for: HKUnit.minute())
                }
                appWorkouts[wk.uuid.uuidString]?.appleExerciseTime = resultCount
                
                print("done processing \(wk.uuid.uuidString)")
            }
            
            print("done processing all workouts")
        } catch {
            print("error:\(error)")
            return [:]
        }
        
        let end = DispatchTime.now()
        let nanoTime = end.uptimeNanoseconds - start.uptimeNanoseconds // <<<<< Difference in nano seconds (UInt64)
        let timeInterval = Double(nanoTime) / 1_000_000_000 // Technically could overflow for long running tests

        print("loadFromHealthKit took \(timeInterval)s")
        return appWorkouts
    }
    
    func getCaloriesForWorkoutSumAsync(for healthStore: HKHealthStore, wk: HKWorkout) async throws -> HKStatistics? {
        
        let workoutPredicate = HKQuery.predicateForObjects(from: wk)
        
        guard let sampleType = HKSampleType.quantityType(forIdentifier: HKQuantityTypeIdentifier.activeEnergyBurned) else {
            fatalError("*** This method should never fail ***")
        }
        
        let predicate = HKSamplePredicate.quantitySample(type: sampleType, predicate: workoutPredicate)
        
        let query = HKStatisticsQueryDescriptor(predicate: predicate, options: .cumulativeSum)
        
        return try await query.result(for: healthStore)
    }
    
    func getAppleExeciseTimeForWorkoutSumAsync(for healthStore: HKHealthStore, wk: HKWorkout) async throws -> HKStatistics? {
        
        let workoutPredicate = HKQuery.predicateForObjects(from: wk)
        
        guard let sampleType = HKSampleType.quantityType(forIdentifier: HKQuantityTypeIdentifier.appleExerciseTime) else {
            fatalError("*** This method should never fail ***")
        }
        
        let predicate = HKSamplePredicate.quantitySample(type: sampleType, predicate: workoutPredicate)
        
        let query = HKStatisticsQueryDescriptor(predicate: predicate, options: .cumulativeSum)
        
        return try await query.result(for: healthStore)
    }
    
    func getDistanceForWorkoutSumAsync(for healthStore: HKHealthStore, wk: HKWorkout) async throws -> HKStatistics? {
        
        let workoutPredicate = HKQuery.predicateForObjects(from: wk)
        
        guard let sampleType = HKSampleType.quantityType(forIdentifier: HKQuantityTypeIdentifier.distanceWalkingRunning) else {
            fatalError("*** This method should never fail ***")
        }
        
        let predicate = HKSamplePredicate.quantitySample(type: sampleType, predicate: workoutPredicate)
        
        let query = HKStatisticsQueryDescriptor(predicate: predicate, options: .cumulativeSum)
        
        return try await query.result(for: healthStore)
    }
    
    func getStepsForWorkoutSumAsync(for healthStore: HKHealthStore, wk: HKWorkout) async throws -> HKStatistics? {
        
        let workoutPredicate = HKQuery.predicateForObjects(from: wk)
        
        guard let sampleType = HKSampleType.quantityType(forIdentifier: HKQuantityTypeIdentifier.stepCount) else {
            fatalError("*** This method should never fail ***")
        }
        
        let predicate = HKSamplePredicate.quantitySample(type: sampleType, predicate: workoutPredicate)
        
        let query = HKStatisticsQueryDescriptor(predicate: predicate, options: .cumulativeSum)
        
        return try await query.result(for: healthStore)
    }
}

class WorkoutService: ObservableObject {
    @Published var allRunningWorkouts: [HKWorkout] = []
    
    typealias DictAppWorkouts = [String: AppWorkoutModel]
    @Published var appWorkouts: DictAppWorkouts
    private var hkWorkouts: [String: HKWorkout] = [:]
    
    private var healthStore: HKHealthStore?
    @Published private(set) var isFetching = false
    private let store = WorkoutServiceStore()
    
    public init(allRunningWorkouts: [HKWorkout] = [],
                appWorkouts: DictAppWorkouts = [:]) {
        self.allRunningWorkouts = allRunningWorkouts
        self.appWorkouts = appWorkouts
        
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
                HKQuantityType.quantityType(forIdentifier: .distanceWalkingRunning)!,
                HKQuantityType.quantityType(forIdentifier: .vo2Max)!,
                HKQuantityType.quantityType(forIdentifier: .stepCount)!,
                HKQuantityType.quantityType(forIdentifier: .nikeFuel)!,
                HKQuantityType.quantityType(forIdentifier: .appleExerciseTime)!
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
    
    func checkFile() -> Bool {
        do {
            let documentDirectory = try FileManager.default.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: false)
            let fileUrl = documentDirectory.appendingPathComponent("appWorkouts.json")
            print(fileUrl)
            if FileManager.default.fileExists(atPath: fileUrl.path) {
                print("FILE AVAILABLE")
                return true
            } else {
                print("FILE NOT AVAILABLE")
            }
        } catch {
            print(error)
        }
        return false
    }
}

extension WorkoutService {
    @MainActor
    func fetchWorkouts(force: Bool = false) async throws {
        var loadedWorkouts: [String:AppWorkoutModel] = [:]
        isFetching = true
        defer { isFetching = false }
        
        let foundFile = checkFile()
        if !foundFile || force {
            loadedWorkouts = await store.loadFromHealthKit(for: healthStore!)
        } else {
            loadedWorkouts = await store.loadFromFile()
        }
        
        appWorkouts = loadedWorkouts
    }
}
