//
//  PhoneCall.swift
//  RosieAI
//
//  Created by Brent Cromley on 1/27/25.
//  This is the interface to initiate a server call from Rosie to a business
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
    let RESERVATION_NAME: String
    let PARTY_SIZE: Int
    let CALLTYPE: String
    let GOAL: String
    let SPECIAL_REQUESTS: String
}

// Define a struct for the expected response from /api/makecall
struct CallResponse: Codable {
    let call_sid: String
    let message: String
}

class PhoneCall: ClientToolProtocol {
    
    private let apiCall: String = "/api/makecall"

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

    func invokeFunction(with parameters: [String: Any]) async throws -> [String: String] {
        print("Input to PhoneCall -> invokeFunction: \(parameters)")

        // Extract and validate the parameters
        guard let partyName = parameters["party_name"] as? String,
              let partySize = parameters["party_size"] as? Int,
              let reservationDateTime = parameters["reservation_date"] as? String,
              let restaurantNumber = parameters["restaurant_phone_number"] as? String else {
            throw NSError(domain: "Invalid parameters for reservation", code: 400, userInfo: nil)
        }

        let restaurantName = parameters["restaurant_name"] as? String ?? "Restaurant"

        // Load configuration
        guard let rosieDomain = Utilities.loadInfoConfig(forKey: "ROSIE_TOPLEVEL_DOMAIN"),
              let fromTeleNumber = Utilities.loadInfoConfig(forKey: "FROM_TELEPHONE_NUMBER"),
              let connectTeleNumber = Utilities.loadInfoConfig(forKey: "CONNECT_TELEPHONE_NUMBER") else {
            throw NSError(domain: "Missing configuration", code: 500, userInfo: nil)
        }

        guard let rosieURL = URL(string: "https://" + rosieDomain + apiCall) else {
            throw NSError(domain: "Invalid URL", code: 500, userInfo: nil)
        }

        // Break up date-time
        let components = reservationDateTime.components(separatedBy: "T")
        guard components.count == 2 else {
            throw NSError(domain: "Incorrect date-time format", code: 400, userInfo: nil)
        }
        let reservationDate = components[0]
        let reservationTime = components[1]

        // Build request body
        let requestBody = PhoneCallRequest(
            TO_NUMBER: restaurantNumber,
            FROM_NUMBER: fromTeleNumber,
            CONNECT_NUMBER: connectTeleNumber,
            RESERVATION_DATE: reservationDate,
            RESERVATION_TIME: reservationTime,
            RESERVATION_NAME: partyName,
            PARTY_SIZE: partySize,
            CALLTYPE: "restaurant",
            GOAL: "Make a restaurant reservation at \(restaurantName)",
            SPECIAL_REQUESTS: ""
        )

        let encoder = JSONEncoder()
        let jsonData = try encoder.encode(requestBody)

        var request = URLRequest(url: rosieURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = jsonData

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                throw NSError(domain: "Server returned an error", code: 500, userInfo: nil)
            }

            let decoder = JSONDecoder()
            let callResponse = try decoder.decode(CallResponse.self, from: data)

            print("Finished making call: \(callResponse.message), callSid: \(callResponse.call_sid)")

            return [
                "message": callResponse.message,
                "callSid": callResponse.call_sid
            ]
        } catch {
            print("Error making POST request: \(error.localizedDescription)")
            throw error
        }
    }
}
