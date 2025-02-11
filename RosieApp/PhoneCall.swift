//
//  PhoneCall.swift
//  RosieApp
//
//  Created by Brent Cromley on 1/27/25.
//


import Foundation

class PhoneCall: ClientToolProtocol {
    // Method to call the phone number of a business
    func makePhoneCall(name: String, phone: String, completion: @escaping (String) -> Void) {
        
        // Dummy URL for your REST API
        guard let url = URL(string: "https://api.example.com/phonecall") else {
            completion("Invalid URL")
            return
        }
        
        // Prepare the request
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        
        // JSON request body
        let parameters: [String: String] = ["name": name, "phone": phone]
        
        // Encode the parameters as JSON
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: parameters, options: [])
            request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        } catch {
            completion("Failed to encode request body")
            return
        }
        
        // Execute the network call
        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                completion("Network error: \(error.localizedDescription)")
                return
            }
            
            guard let data = data else {
                completion("No data received")
                return
            }
            
            // Handle API response
            if let responseString = String(data: data, encoding: .utf8) {
                completion("API Response: \(responseString)")
            } else {
                completion("Unable to decode response")
            }
        }
        
        task.resume()
    }
    
    func getParameters() -> [String: Any] {
        return [
            "type": "function",
            "name": "make_phone_call",
            "description": "Make a reservation at a restaurant for a specific= date and time for the desired party size and name to hold the reservation under.",
            "parameters": [
                "type": "object",
                "properties": [
                    "restaurant_name": [
                        "type": "string",
                        "description": "Name of Restaurant"
                    ],
                    "phone_number": [
                        "type": "string",
                        "description": "Telephone Number for restaurant"
                    ],
                    "party_size": [
                        "type": "int",
                        "description": "Number of people for the reservation"
                    ],
                    "reservation_name": [
                        "type": "string",
                        "description": "Name that will be used for the reservation"
                    ]
                ],
                "required": ["name", "phone_number", "party_size", "reservation_name"]
            ]
        ]
    }

    func invokeFunction(with parameters: [String: Any]) async throws -> String
    {
        print("Phone Call - invoke function called.")
        print("Received JSON dictionary: \(parameters)")

        // Extract and validate the parameters
        guard let restaurantName = parameters["restaurant_name"] as? String,
              let telephoneNumber = parameters["phone_number"] as? String,
              let partySize = parameters["party_size"] as? Int,
              let reservationName = parameters["reservation_name"] as? String else {
            throw NSError(domain: "Invalid name or city", code: 400, userInfo: nil)
        }

        // Check if both 'city' and 'name' are present in the dictionary and have string values
        if let city = parameters["city"] as? String, let restaurant = parameters["name"] as? String {
        }
        // Example implementation that initiates a phone call based on parameters
        guard let phoneNumber = parameters["phoneNumber"] as? String else {
            throw NSError(domain: "InvalidParameters", code: 400, userInfo: nil)
        }
        return "Calling \(phoneNumber)..."
    }
}
