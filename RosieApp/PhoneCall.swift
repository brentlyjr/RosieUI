//
//  PhoneCall.swift
//  RosieApp
//
//  Created by Brent Cromley on 1/27/25.
//


// Currently, calls to the Rosie API for initiating a phone call need to adhere to the
// following API format:
//
//      "TO_NUMBER": "+14157063926",
//      "FROM_NUMBER": "+14066318974",
//      "CONNECT_NUMBER": "+12484345508",
//      "RESERVATION_DATE": "2025-02-12",
//      "RESERVATION_TIME": "19:30",
//      "RESERVATION_NAME": "Brent Cromley",
//      "PARTY_SIZE": "2",
//      "CALLTYPE": "restaurant",
//      "GOAL": "Make a restaurant reservation",
//      "SPECIAL_REQUESTS": "eat outside, please"
//

import Foundation

struct PhoneCallRequest: Codable {
    let TO_NUMBER: String
    let FROM_NUMBER: String
    let CONNECT_NUMBER: String
    let RESERVATION_DATE: String
    let RESERVATION_TIME: String
    let PARTY_NAME: String
    let PARTY_SIZE: Int
    let CALLTYPE: String
    let GOAL: String
    let SPECIAL_REQUESTS: String
}

class PhoneCall: ClientToolProtocol {
    
    func getParameters() -> [String: Any] {
        return [
            "type": "function",
            "name": "make_phone_call",
            "description": "Make a reservation at a restaurant for a specific date and time for the desired party size and name to hold the reservation under.",
            "parameters": [
                "type": "object",
                "properties": [
                    "party_name": [
                        "type": "string",
                        "description": "Name the reservation will be made under"
                    ],
                    "party_size": [
                        "type": "integer",
                        "description": "Number of people for the reservation"
                    ],
                    "reservation_date": [
                        "type": "string",
                        "description": "Date and time of the reservation in ISO 8601 format"
                    ],
                    "restaurant_name": [        // Restaurant name is optional, we don't need this parameter
                        "type": "string",
                        "description": "Name of Restaurant"
                    ],
                    "restaurant_phone_number": [
                        "type": "string",
                        "description": "Telephone Number for restaurant"
                    ],
                ],
                "required": ["party_name", "party_size", "restaurant_phone_number", "reservation_date"]
            ]
        ]
    }

    func invokeFunction(with parameters: [String: Any]) async throws -> String
    {
        print("Phone Call - invoke function called.")
        print("Received JSON dictionary: \(parameters)")

        // Extract and validate the parameters
        guard let partyName = parameters["party_name"] as? String,
              let partySize = parameters["party_size"] as? Int,
              let reservationDate = parameters["reservation_date"] as? String,
              let restaurantNumber = parameters["restaurant_phone_number"] as? String else {
            throw NSError(domain: "Invalid parameters for reservation", code: 400, userInfo: nil)
        }

        let restaurantName = parameters["restaurant_name"] as? String ?? "Restaurant"

        // We need to get some of our variables from our configuration to complete the API call
        guard let rosieAPI = Utilities.loadInfoConfig(forKey: "ROSIE_API_URL") else {
            print("Failed to load ROSIE_API_URL from Info.plist")
            return "Unable to load ROSIE_API_URL from Info.plist"
        }

        guard let rosieURL = URL(string: rosieAPI) else {
            print("Unable to construct URL from ROSIE_API_URL")
            return "Unable to construct URL from ROSIE_API_URL"
        }

        guard let fromTeleNumber = Utilities.loadInfoConfig(forKey: "FROM_TELEPHONE_NUMBER") else {
            print("Failed to load FROM_TELEPHONE_NUMBER from Info.plist")
            return "Unable to load FROM_TELEPHONE_NUMBER from Info.plist"
        }

        // Build up our request body to send into our API call
        let requestBody = PhoneCallRequest(
            TO_NUMBER: restaurantNumber,
            FROM_NUMBER: fromTeleNumber,
            CONNECT_NUMBER: "+12484345508",
            RESERVATION_DATE: "2025-02-14",
            RESERVATION_TIME: "19:30",
            PARTY_NAME: partyName,
            PARTY_SIZE: partySize,
            CALLTYPE: "restaurant",
            GOAL: "Make a restaurant reservation at \(restaurantName)",
            SPECIAL_REQUESTS: "eat outside, please"
        )

        // 3. Encode the request body to JSON data
        let encoder = JSONEncoder()
        do {
            let jsonData = try encoder.encode(requestBody)
            
            // 4. Create and configure the URLRequest
            var request = URLRequest(url: rosieURL)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = jsonData
            
            // 5. Create a URLSession data task to send the request
            let task = URLSession.shared.dataTask(with: request) { data, response, error in
                if let error = error {
                    print("Error making POST request: \(error.localizedDescription)")
                    return
                }
                
                if let data = data, let responseString = String(data: data, encoding: .utf8) {
                    print("Response from server: \(responseString)")
                } else {
                    print("No data received from the server.")
                }
            }
            // 6. Start the task
            task.resume()
        } catch {
            print("Failed to encode request body: \(error.localizedDescription)")
        }

        return "Calling \(restaurantNumber)..."
    }
}
