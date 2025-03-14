//
//  Utilities.swift
//  RosieAI
//
//  Created by Brent Cromley on 1/27/25.
//  Utility functions needed by Rosie
//

import Foundation

class Utilities {
    
    // Loads a secret value from a Secrets.plist file.
    static func loadSecret(forKey key: String) -> String? {
        guard let url = Bundle.main.url(forResource: "Secrets", withExtension: "plist"),
              let data = try? Data(contentsOf: url),
              let secrets = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else {
            print("Failed to load secrets from Secrets.plist")
            return nil
        }
        
        return secrets[key] as? String
    }
    
    static func loadInfoConfig(forKey key:String) -> String? {
        guard let url = Bundle.main.url(forResource: "Info", withExtension: "plist"),
              let data = try? Data(contentsOf: url),
              let info = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else {
            print("Failed to load \(key) from Info.plist")
            return nil
        }
        return info[key] as? String
    }
    
    static func loadPrompt(forKey key: String) -> String? {
        guard let url = Bundle.main.url(forResource: "Prompts", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let jsonObject = try? JSONSerialization.jsonObject(with: data, options: []),
              let prompts = jsonObject as? [String: String] else {
            print("Failed to load prompts.json")
            return nil
        }
        return prompts[key]
    }
}
