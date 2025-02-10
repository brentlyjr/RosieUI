//
//  ClientToolProtocol.swift
//  RosieApp
//
//  Created by Brent Cromley on 2/6/25.
//

protocol ClientToolProtocol {
    
    func getParameters() -> [String: Any]

    func parseParameters()

    func invokeFunction()
}
