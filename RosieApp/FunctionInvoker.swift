//
//  FunctionInvoker.swift
//  RosieApp
//
//  Created by Brent Cromley on 1/15/25.
//


import Foundation

class FunctionInvoker {
    // Map function names to instances of classes that conform to ClientToolProtocol
    private var functionMap: [String: ClientToolProtocol] = [:]

    // Register a class instance in the function map
    func addFunction<T: ClientToolProtocol>(_ name: String, instance: T) {
        functionMap[name] = instance
    }

    // Invoke the function asynchronously
    func invoke(functionName: String, parameters: [String: Any]) async -> Result<String, Error> {
        guard let functionInstance = functionMap[functionName] else {
            return .failure(FunctionError.notFound(functionName))
        }

        do {
            // Call the method directly on the instance
            let result = try await functionInstance.invokeFunction(with: parameters)
            return .success(result)
        } catch {
            return .failure(error)
        }
    }

    // Custom error type for missing functions
    enum FunctionError: Error {
        case notFound(String)
        case invalidType // Added missing case
    }
}
