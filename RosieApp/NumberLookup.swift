//
//  NumberLookup.swift
//  RosieApp
//
//  Created by Brent Cromley on 1/14/25.
//

import Foundation

class NumberLookup {
    private let subscriptionKey = "5f6416b0e1e048fca03abc1be29512ab" // Replace with your Bing API key
    
    // Method to look up a phone number for a restaurant
    func lookupPhoneNumber(name: String, city: String, completion: @escaping (String) -> Void) {
        print("**** Looking up phone number!!!!!")
        
        // Validate input parameters
        guard !name.isEmpty, !city.isEmpty else {
            completion("Error: Please provide both a restaurant name and a city name.")
            return
        }
        
        // Construct the API endpoint
        let query = "\(name) restaurant in \(city)"
        guard let encodedQuery = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://api.bing.microsoft.com/v7.0/entities?q=\(encodedQuery)&mkt=en-US") else {
            completion("Error: Failed to construct the API URL.")
            return
        }
        
        // Create the request
        var request = URLRequest(url: url)
        request.addValue(subscriptionKey, forHTTPHeaderField: "Ocp-Apim-Subscription-Key")
        
        // Perform the API request
        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            // Handle network errors
            if let error = error {
                completion("Error: \(error.localizedDescription)")
                return
            }
            
            // Validate the response data
            guard let data = data else {
                completion("Error: No data received from the server.")
                return
            }
            
            // Parse the JSON response
            do {
                if let json = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any],
                   let places = json["places"] as? [String: Any],
                   let values = places["value"] as? [[String: Any]] {
                    
                    // Search for the restaurant entity
                    if let restaurant = values.first(where: { entity in
                        let entityName = (entity["name"] as? String)?.lowercased() ?? ""
                        let hints = (entity["entityPresentationInfo"] as? [String: Any])?["entityTypeHints"] as? [String]
                        return entityName.contains(name.lowercased()) && hints?.contains("Restaurant") == true
                    }) {
                        // Extract the phone number
                        if let phoneNumber = restaurant["telephone"] as? String ??
                            (restaurant["contact"] as? [String: String])?["phone"] {
                            completion("The phone number for \(name) in \(city) is \(phoneNumber).")
                        } else {
                            completion("No phone number found for \(name) in \(city).")
                        }
                    } else {
                        completion("No matching restaurant found for \(name) in \(city).")
                    }
                } else {
                    completion("No results found for \(name) in \(city).")
                }
            } catch {
                completion("Error: Failed to parse server response.")
            }
        }
        
        task.resume()
    }
}
