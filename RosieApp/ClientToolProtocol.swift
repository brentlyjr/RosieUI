//
//  ClientToolProtocol.swift
//  RosieApp
//
//  Created by Brent Cromley on 2/6/25.
//

protocol ClientToolProtocol {
    
    func getParameters() -> [String: Any]
    
    // Invokes the function with the given parameters asynchronously.
    func invokeFunction(with parameters: [String: Any]) async throws -> String
}
