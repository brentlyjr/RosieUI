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
            "description": "Make a phone call to a business with the provided number.",
            "parameters": [
                "type": "object",
                "properties": [
                    "name": [
                        "type": "string",
                        "description": "Name of Business"
                    ],
                    "phone_number": [
                        "type": "string",
                        "description": "Telephone Number for business"
                    ]
                ],
                "required": ["name", "phone_number"]
            ]
        ]
    }

    func parseParameters() { print("parsing parameters") }
    func invokeFunction() { print("invoking funtion") }
}
