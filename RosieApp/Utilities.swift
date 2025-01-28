//
//  Utilities.swift
//  RosieApp
//
//  Created by Brent Cromley on 1/27/25.
//

import Foundation

class Utilities {
    /// Loads a secret value from a Secrets.plist file.
    static func loadSecret(forKey key: String) -> String? {
        guard let url = Bundle.main.url(forResource: "Secrets", withExtension: "plist"),
              let data = try? Data(contentsOf: url),
              let secrets = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else {
            print("Failed to load secrets from Secrets.plist")
            return nil
        }
        
        return secrets[key] as? String
    }
}
