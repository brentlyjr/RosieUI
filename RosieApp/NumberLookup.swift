//
//  NumberLookup.swift
//  RosieApp
//
//  Created by Brent Cromley on 1/14/25.
//

import Foundation

class NumberLookup: ClientToolProtocol {

    // Parameters required for our client tool on OpenAI
    func getParameters() -> [String: Any] {
        return [
            "type": "function",
            "name": "restaurant_phone_lookup",
            "description": "Looks up the phone number of a restaurant based on its name and city.",
            "parameters": [
                "type": "object",
                "properties": [
                    "name": [
                        "type": "string",
                        "description": "Name of Restaurant"
                    ],
                    "city": [
                        "type": "string",
                        "description": "City restaurant is in"
                    ]
                ],
                "required": ["name", "city"]
            ]
        ]
    }
    
    // Will be invoked when OpenAI requires us to look up a phone number
    func invokeFunction(with parameters: [String: Any]) async throws -> String {
        print("NumberLookup - invoke function called.")
        print("Received JSON dictionary: \(parameters)")
        
        // Extract and validate the parameters
        guard let city = parameters["city"] as? String,
              let restaurantName = parameters["name"] as? String else {
            throw NSError(domain: "Invalid name or city", code: 400, userInfo: nil)
        }
        
        // This is test code so I can control what number is being called
        // We should see if we are in TEST_MODE = Yes
        // And if so, we will just return the phone number provided
        if let testMode = Utilities.loadInfoConfig(forKey: "TEST_MODE"),
           testMode.uppercased() == "YES",
           let testPhoneNumber = Utilities.loadInfoConfig(forKey: "TEST_PHONE_NUMBER"),
           !testPhoneNumber.isEmpty {
            
            return "The phone number for \(restaurantName) is \(testPhoneNumber)"
        }

        // If we pass through, we are not in test mode, so need to lookup the phone number

        // Get the API key for the Bing query
        guard let bingAPIKey = Utilities.loadSecret(forKey: "BING_API_KEY") else {
            print("Failed to load BING_API_KEY from Secrets.plist")
            return "Unable to load BING_API_KEY from Secrets.plist"
        }
        
        guard let bingURL = Utilities.loadInfoConfig(forKey: "BING_API_URL") else {
            print("Failed to load BING_API_URL from Info.plist")
            return "Unable to load BING_API_URL from Info.plist"
        }
        
        // Construct the API endpoint
        let query = "\(restaurantName) restaurant in \(city)"
        guard let encodedQuery = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "\(bingURL)?q=\(encodedQuery)&mkt=en-US") else {
            return "Failed to construct the API URL"
        }
        
        // Create the request and add the API key header
        var request = URLRequest(url: url)
        request.addValue(bingAPIKey, forHTTPHeaderField: "Ocp-Apim-Subscription-Key")
        
        // Perform the API request using async/await
        let (data, _) = try await URLSession.shared.data(for: request)
        
        // Ensure we received data
        guard !data.isEmpty else {
            return "Error: No data received from the server."
        }
        
        // Parse the JSON response
        do {
            // Convert the data to a JSON dictionary
            if let json = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any],
               let places = json["places"] as? [String: Any],
               let values = places["value"] as? [[String: Any]] {
                
                // Look for the matching restaurant entity
                if let restaurantEntity = values.first(where: { entity in
                    let entityName = (entity["name"] as? String)?.lowercased() ?? ""
                    let hints = (entity["entityPresentationInfo"] as? [String: Any])?["entityTypeHints"] as? [String]
                    return entityName.contains(restaurantName.lowercased()) && hints?.contains("Restaurant") == true
                }) {
                    // Try to extract the phone number from either "telephone" or a nested "contact" dictionary
                    if let phoneNumber = restaurantEntity["telephone"] as? String ??
                        ((restaurantEntity["contact"] as? [String: Any])?["phone"] as? String) {
                        return "The phone number for \(restaurantName) in \(city) is \(phoneNumber)."
                    } else {
                        return "No phone number found for \(restaurantName) in \(city)."
                    }
                } else {
                    return "No matching restaurant found for \(restaurantName) in \(city)."
                }
            } else {
                return "No results found for \(restaurantName) in \(city)."
            }
        } catch {
            return "Error: Failed to parse server response."
        }
    }
}
