//
//  FunctionInvoker.swift
//  RosieApp
//
//  Created by Brent Cromley on 1/15/25.
//


import Foundation

class FunctionInvoker {
    // Map function names to closures that take two String parameters and a completion closure
    private var functionMap: [String: (String, String, @escaping (String) -> Void) -> Void] = [:]

    // Add a function to the map dynamically
    func addFunction(_ name: String, function: @escaping (String, String, @escaping (String) -> Void) -> Void) {
        functionMap[name] = function
    }

    // Invoke a function by name
    func invoke(functionName: String, param1: String, param2: String, completion: @escaping (String) -> Void) {
        if let function = functionMap[functionName] {
            // Here, we call the function and provide the passed-in completion closure
            function(param1, param2, completion)
        } else {
            print("Error: Function '\(functionName)' not found")
        }
    }
}
