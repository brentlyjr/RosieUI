//
//  ClientToolProtocol.swift
//  RosieAI
//
//  Created by Brent Cromley on 2/6/25.
//  A protocol definition for a ClientTool as defined by OpenAI
//

protocol ClientToolProtocol {
    
    // This returns the parameters that define the ClientTool
    func getParameters() -> [String: Any]
    
    // Invokes the function with the given parameters asynchronously.
    func invokeFunction(with parameters: [String: Any]) async throws -> [String: String]
}
