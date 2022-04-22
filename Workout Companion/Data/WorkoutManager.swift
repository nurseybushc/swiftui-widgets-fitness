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
    
    typealias DictAppWorkouts = [String: AppWorkoutModel]
    @Published var appWorkouts: DictAppWorkouts = [:]
    private var hkWorkouts: [String: HKWorkout] = [:]
    
    private var healthStore: HKHealthStore?
    private let batchCount = 10
    
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
    
    func executionsDoneBatch(startIndex: Int, endIndex: Int){
        print("executionsDoneBatch \(startIndex)-\(endIndex)")
        
        let newStartIndex = endIndex + 1
        let newEndIndex = newStartIndex + (batchCount-1)
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
            self.processRunningWorkoutsBatch(startIndex: newStartIndex, endIndex: newEndIndex)
        }
    }
    
    func executionsDone() {
        print("executionsDone")
        
        print("\(appWorkouts.count) appWorkouts")
        
        do {
            
            let jsonData = try JSONEncoder().encode(appWorkouts)
            let jsonString = String(data: jsonData, encoding: .utf8)!
            
            print(NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true).last)
            
            if let documentDirectory = FileManager.default.urls(for: .documentDirectory,
                                                                in: .userDomainMask).first {
                let pathWithFilename = documentDirectory.appendingPathComponent("appWorkouts.json")
                do {
                    try jsonString.write(to: pathWithFilename,
                                         atomically: true,
                                         encoding: .utf8)
                } catch {
                    print("try jsonWrite \(error)")
                }
            }
        } catch { print("do \(error)") }
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
    
    func loadWorkoutData() {
        print("loadWorkoutData")
        latestMapWorkout()
        latestWorkoutWeekDays()
        latestWorkouts()
        let foundFile = checkFile()
        if !foundFile {
            getAllRunningWorkouts()
        } else {
            loadFromFile()
        }
    }
    
    func loadFromFile(){
        
        do {
            let documentDirectory = try FileManager.default.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: false)
            let fileUrl = documentDirectory.appendingPathComponent("appWorkouts.json")
            let data = try Data(contentsOf: fileUrl)
            let decoder = JSONDecoder()
            appWorkouts = try decoder.decode(DictAppWorkouts.self, from: data)

            print("loadFromFile appWorkouts.count \(appWorkouts.count)")
        } catch {
            print("error:\(error)")
        }
    }
    
    func checkFile() -> Bool{
        do {
            let documentDirectory = try FileManager.default.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: false)
            let fileUrl = documentDirectory.appendingPathComponent("appWorkouts.json")
            print(fileUrl)
            if FileManager.default.fileExists(atPath: fileUrl.path) {
                print("FILE AVAILABLE")
                let fileAttributes = try! FileManager.default.attributesOfItem(atPath: fileUrl.path)
                let fileSizeNumber = fileAttributes[FileAttributeKey.size] as! NSNumber
                let fileSize = fileSizeNumber.int64Value
                //var sizeMB = Double(fileSize / 1024)
                //sizeMB = Double(sizeMB / 1024)
                print(String(format: "%.2f", fileSize) + " bytes")
                return true
            } else {
                print("FILE NOT AVAILABLE")
            }
        } catch {
            print(error)
        }
        return false
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
    
    func processRunningWorkouts(wks: [HKWorkout]){
        print("processing running workouts...")
        
        for wk in wks {
            self.appWorkouts[wk.uuid.uuidString] = AppWorkoutModel(id:wk.uuid.uuidString, startDate: wk.startDate, endDate: wk.endDate, duration: wk.duration)
            self.hkWorkouts[wk.uuid.uuidString] = wk
            
            if let metadata = wk.metadata {
                if let avgMets = metadata[HKMetadataKeyAverageMETs] {
                    if let avgMetsQuant = avgMets as? HKQuantity {
                        let mets = avgMetsQuant.doubleValue(for: HKUnit.kilocalorie().unitDivided(by: HKUnit.gramUnit(with: .kilo).unitMultiplied(by: HKUnit.hour())))
                        
                        self.appWorkouts[wk.uuid.uuidString]?.mets = mets
                    }
                }
            }
        }
        processRunningWorkoutsBatch(startIndex: 0, endIndex: self.batchCount - 1)
    }
    
    func processRunningWorkoutsBatch(startIndex: Int, endIndex: Int){
        print("processRunningWorkoutsBatch \(startIndex) - \(endIndex)...")
        
        let dispatchGroup = DispatchGroup()
        let queue = DispatchQueue(label: "com.gcd.dispatchGroup", attributes: .concurrent)
        let semaphore = DispatchSemaphore(value: 1)
        
        let keys = appWorkouts.keys
        var keysArr = [String]()
        keysArr.append(contentsOf: keys)
        
        if startIndex >= keys.count {
            executionsDone()
            return
        }
        var newEndIndex = endIndex
        if endIndex > keys.count - 1 {
            newEndIndex = keys.count - 1
        }
        
        for index in startIndex...newEndIndex {
            guard let appWorkout = appWorkouts[keysArr[index]] else {
                continue
            }
            guard let wk = hkWorkouts[appWorkout.id] else {
                continue
            }
                        
            let getCaloriesDWI = DispatchWorkItem {
                self.getCaloriesForWorkoutSum(wk: wk, queue: queue, dispatchGroup: dispatchGroup, semaphore: semaphore)
            }
            let getDistanceDWI = DispatchWorkItem {
                self.getDistanceForWorkoutSum(wk: wk, queue: queue, dispatchGroup: dispatchGroup, semaphore: semaphore)
            }
            let getStepsDWI = DispatchWorkItem {
                self.getStepsForWorkout3Sum(wk: wk, queue: queue, dispatchGroup: dispatchGroup, semaphore: semaphore)
            }
            let getAppExerciseTimeDWI = DispatchWorkItem {
                self.getAppleExeciseTimeForWorkoutSum(wk: wk, queue: queue, dispatchGroup: dispatchGroup, semaphore: semaphore)
            }
            
            getStepsDWI.notify(queue: queue, execute: getAppExerciseTimeDWI)
            getDistanceDWI.notify(queue: queue, execute: getStepsDWI)
            getCaloriesDWI.notify(queue: queue, execute: getDistanceDWI)
            
            queue.async(execute: getCaloriesDWI)
        }
        
        dispatchGroup.notify(queue: .main) { [self] in
            executionsDoneBatch(startIndex: startIndex, endIndex: newEndIndex)
        }
    }
    
    
    func getStepsForWorkout3(wk: HKWorkout, queue: DispatchQueue, dispatchGroup: DispatchGroup){
        dispatchGroup.enter()
        let sampleType = HKQuantityType.quantityType(forIdentifier: .stepCount)!
        let predicate = HKQuery.predicateForObjects(from: wk)
        
        let query = HKSampleQuery(
            sampleType: sampleType,
            predicate: predicate,
            limit: Int(HKObjectQueryNoLimit),
            sortDescriptors: nil) { (query, results, error) in
                queue.async {
                    guard let wkSamples = results else {
                        print("workout \(wk.uuid) has no steps samples")
                        return
                    }
                    
                    print("getStepsForWorkout3 workout \(wk.uuid) has \(wkSamples.count) steps samples")
                    dispatchGroup.leave()
                }
            }
        HKHealthStore().execute(query)
    }
    
    func getStepsForWorkout3Sum(wk: HKWorkout, queue: DispatchQueue, dispatchGroup: DispatchGroup, semaphore: DispatchSemaphore){
        dispatchGroup.enter()
                
        let sampleType = HKQuantityType.quantityType(forIdentifier: .stepCount)!
        let predicate = HKQuery.predicateForObjects(from: wk)
        
        let query = HKStatisticsQuery(quantityType: sampleType, quantitySamplePredicate: predicate, options: .cumulativeSum ) { (_, result, error) in
            
            queue.async {
                var resultCount = 0.0
                
                guard let result = result else { return }
                
                if let sum = result.sumQuantity() {
                    resultCount = sum.doubleValue(for: HKUnit.count())
                }
                
                semaphore.wait()
                self.appWorkouts[wk.uuid.uuidString]?.steps = resultCount
                semaphore.signal()
                dispatchGroup.leave()
            }
        }
        
        HKHealthStore().execute(query)
    }
    
    func getStepsForWorkoutTimes(wk: HKWorkout, queue: DispatchQueue, dispatchGroup: DispatchGroup){
        dispatchGroup.enter()
        let sampleType = HKQuantityType.quantityType(forIdentifier: .stepCount)!
        
        print("getStepsForWorkoutTimes wk:\(wk.uuid), startDate: \(wk.startDate), endDate: \(wk.endDate)")
        let predicate = HKQuery.predicateForSamples(withStart: wk.startDate, end: wk.endDate)
        
        let query = HKSampleQuery(
            sampleType: sampleType,
            predicate: predicate,
            limit: Int(HKObjectQueryNoLimit),
            sortDescriptors: nil) { (query, results, error) in
                queue.async {
                    guard let wkSamples = results else {
                        print("workout \(wk.uuid) has no steps samples")
                        return
                    }
                    
                    print("workout \(wk.uuid) has \(wkSamples.count) steps samples")

                    dispatchGroup.leave()
                }
            }
        HKHealthStore().execute(query)
    }
    
    func getDistanceForWorkout(wk: HKWorkout, queue: DispatchQueue, dispatchGroup: DispatchGroup){
        dispatchGroup.enter()
        let workoutPredicate = HKQuery.predicateForObjects(from: wk)
        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierEndDate,
                                              ascending: true)
        
        guard let sampleType = HKSampleType.quantityType(forIdentifier: HKQuantityTypeIdentifier.distanceWalkingRunning) else {
            fatalError("*** This method should never fail ***")
        }
        
        let query = HKSampleQuery(sampleType: sampleType,
                                  predicate: workoutPredicate,
                                  limit: Int(HKObjectQueryNoLimit),
                                  sortDescriptors: [sortDescriptor])
        { (query, samples, error) in
            
            queue.async {
                guard let wkSamples = samples else { return }
                if wkSamples.count > 0 {
                    print("workout \(wk.uuid) has \(wkSamples.count) distance samples")
                    
                }
                dispatchGroup.leave()
            }
        }
        
        HKHealthStore().execute(query)
    }
    
    func getDistanceForWorkoutSum(wk: HKWorkout, queue: DispatchQueue, dispatchGroup: DispatchGroup, semaphore: DispatchSemaphore){
        dispatchGroup.enter()
                
        let workoutPredicate = HKQuery.predicateForObjects(from: wk)
        
        guard let sampleType = HKSampleType.quantityType(forIdentifier: HKQuantityTypeIdentifier.distanceWalkingRunning) else {
            fatalError("*** This method should never fail ***")
        }
        
        let query = HKStatisticsQuery(quantityType: sampleType, quantitySamplePredicate: workoutPredicate, options: .cumulativeSum ) { (_, result, error) in
            
            queue.async {
                var resultCount = 0.0
                
                guard let result = result else { return }
                
                if let sum = result.sumQuantity() {
                    resultCount = sum.doubleValue(for: HKUnit.mile())
                }
                                
                semaphore.wait()
                self.appWorkouts[wk.uuid.uuidString]?.totalDistance = resultCount
                semaphore.signal()
                dispatchGroup.leave()
            }
        }
        
        HKHealthStore().execute(query)
    }
    
    // no vo2max samples
    func getVo2MaxForWorkout(wk: HKWorkout, queue: DispatchQueue, dispatchGroup: DispatchGroup){
        dispatchGroup.enter()
        let kgmin = HKUnit.gramUnit(with: .kilo).unitMultiplied(by: .minute())
        let mL = HKUnit.literUnit(with: .milli)
        let VO₂Unit = mL.unitDivided(by: kgmin)
        
        let predicate = HKQuery.predicateForSamples(withStart: wk.startDate, end: wk.endDate)
        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierEndDate,
                                              ascending: true)
        
        guard let sampleType = HKSampleType.quantityType(forIdentifier: HKQuantityTypeIdentifier.vo2Max) else {
            fatalError("*** This method should never fail ***")
        }
        
        let query = HKSampleQuery(sampleType: sampleType,
                                  predicate: predicate,
                                  limit: Int(HKObjectQueryNoLimit),
                                  sortDescriptors: [sortDescriptor])
        { (query, samples, error) in
            
            queue.async {
                guard let wkSamples = samples else { return }
                if wkSamples.count > 0 {
                    print("workout \(wk.uuid) has \(wkSamples.count) vo2max samples")
                    
                }
                dispatchGroup.leave()
            }
        }
        
        HKHealthStore().execute(query)
    }
    
    
    func getAppleExeciseTimeForWorkout(wk: HKWorkout, queue: DispatchQueue, dispatchGroup: DispatchGroup){
        dispatchGroup.enter()
        
        print("workout \(wk.uuid) sum appleExerciseTime starting...")
        
        let predicate = HKQuery.predicateForSamples(withStart: wk.startDate, end: wk.endDate)
        
        guard let sampleType = HKSampleType.quantityType(forIdentifier: HKQuantityTypeIdentifier.appleExerciseTime) else {
            fatalError("*** This method should never fail ***")
        }
        
        let query = HKSampleQuery(sampleType: sampleType,
                                  predicate: predicate,
                                  limit: Int(HKObjectQueryNoLimit),
                                  sortDescriptors: nil)
        { (query, samples, error) in
            
            queue.async {
                guard let wkSamples = samples else { return }
                print("workout \(wk.uuid) has \(wkSamples.count) appleexercisetime samples")
                
                dispatchGroup.leave()
            }
        }
        
        
        HKHealthStore().execute(query)
    }
    
    func getAppleExeciseTimeForWorkoutSum(wk: HKWorkout, queue: DispatchQueue, dispatchGroup: DispatchGroup, semaphore: DispatchSemaphore){
        dispatchGroup.enter()
                
        let predicate = HKQuery.predicateForSamples(withStart: wk.startDate, end: wk.endDate)
        
        guard let sampleType = HKSampleType.quantityType(forIdentifier: HKQuantityTypeIdentifier.appleExerciseTime) else {
            fatalError("*** This method should never fail ***")
        }
        
        let query = HKStatisticsQuery(quantityType: sampleType, quantitySamplePredicate: predicate, options: .cumulativeSum ) { (_, result, error) in
            
            queue.async {
                var resultCount = 0.0
                
                guard let result = result else { return }
                
                if let sum = result.sumQuantity() {
                    resultCount = sum.doubleValue(for: HKUnit.minute())
                }
                                
                semaphore.wait()
                self.appWorkouts[wk.uuid.uuidString]?.appleExerciseTime = resultCount
                semaphore.signal()
                dispatchGroup.leave()
            }
        }
        
        HKHealthStore().execute(query)
    }
    
    func getCaloriesForWorkout(wk: HKWorkout, queue: DispatchQueue, dispatchGroup: DispatchGroup){
        dispatchGroup.enter()
        let workoutPredicate = HKQuery.predicateForObjects(from: wk)
        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierEndDate,
                                              ascending: true)
        
        guard let sampleType = HKSampleType.quantityType(forIdentifier: HKQuantityTypeIdentifier.activeEnergyBurned) else {
            fatalError("*** This method should never fail ***")
        }
        
        let query = HKSampleQuery(sampleType: sampleType,
                                  predicate: workoutPredicate,
                                  limit: Int(HKObjectQueryNoLimit),
                                  sortDescriptors: [sortDescriptor])
        { (query, samples, error) in
            
            queue.async {
                guard let wkSamples = samples else { return }
                print("workout \(wk.uuid) has \(wkSamples.count) calorie samples")

                
                dispatchGroup.leave()
            }
        }
        
        HKHealthStore().execute(query)
    }
    
    func getCaloriesForWorkoutSum(wk: HKWorkout, queue: DispatchQueue, dispatchGroup: DispatchGroup, semaphore: DispatchSemaphore){
        dispatchGroup.enter()
                
        let workoutPredicate = HKQuery.predicateForObjects(from: wk)
        
        guard let sampleType = HKSampleType.quantityType(forIdentifier: HKQuantityTypeIdentifier.activeEnergyBurned) else {
            fatalError("*** This method should never fail ***")
        }
        
        let query = HKStatisticsQuery(quantityType: sampleType, quantitySamplePredicate: workoutPredicate, options: .cumulativeSum ) { (_, result, error) in
            
            queue.async {
                var resultCount = 0.0
                
                guard let result = result else { return }
                
                if let sum = result.sumQuantity() {
                    resultCount = sum.doubleValue(for: HKUnit.kilocalorie())
                }
                                
                semaphore.wait()
                self.appWorkouts[wk.uuid.uuidString]?.totalEeneryBurned = resultCount
                semaphore.signal()
                dispatchGroup.leave()
            }
        }
        
        HKHealthStore().execute(query)
    }
    
    func getHeartRateForWorkoutTimes(wk: HKWorkout, queue: DispatchQueue, dispatchGroup: DispatchGroup){
        dispatchGroup.enter()
        
        let predicate = HKQuery.predicateForSamples(withStart: wk.startDate, end: wk.endDate)
        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierEndDate,
                                              ascending: true)
        
        guard let sampleType = HKSampleType.quantityType(forIdentifier: HKQuantityTypeIdentifier.heartRate) else {
            fatalError("*** This method should never fail ***")
        }
        
        let query = HKSampleQuery(sampleType: sampleType,
                                  predicate: predicate,
                                  limit: Int(HKObjectQueryNoLimit),
                                  sortDescriptors: [sortDescriptor])
        { (query, samples, error) in
            
            queue.async {
                guard let wkSamples = samples else { return }

                dispatchGroup.leave()
            }
        }
        
        HKHealthStore().execute(query)
    }
    
    func getHeartRateForWorkout(wk: HKWorkout, queue: DispatchQueue, dispatchGroup: DispatchGroup){
        dispatchGroup.enter()
        
        let predicate = HKQuery.predicateForObjects(from: wk)
        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierEndDate,
                                              ascending: true)
        
        guard let sampleType = HKSampleType.quantityType(forIdentifier: HKQuantityTypeIdentifier.heartRate) else {
            fatalError("*** This method should never fail ***")
        }
        
        let query = HKSampleQuery(sampleType: sampleType,
                                  predicate: predicate,
                                  limit: Int(HKObjectQueryNoLimit),
                                  sortDescriptors: [sortDescriptor])
        { (query, samples, error) in
            
            queue.async {
                guard let wkSamples = samples else { return }

                dispatchGroup.leave()
            }
        }
        
        HKHealthStore().execute(query)
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
