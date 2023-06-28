//
//  AjoInboundConsequence.swift
//  AEPMessaging
//
//  Created by steve benedick on 5/19/23.
//

import Foundation
import AEPServices

class AjoInboundConsequence: Codable {
    var type: AjoInboundType
    var content: AnyCodable
    var contentType: String
    var expiryDate: Date
    var meta: [String: AnyCodable]?
    
//    enum CodingKeys: String, CodingKey {
//        case type
//        case content
//        case contentType
//        case expiryDate
//        case meta
//    }
    
    init(type: AjoInboundType, content: AnyCodable, contentType: String, expiryDate: Date, meta: [String : AnyCodable]? = nil) {
        self.type = type
        self.content = content
        self.contentType = contentType
        self.expiryDate = expiryDate
        self.meta = meta
    }
    
//    required init(from decoder: Decoder) throws {
//        let values = try decoder.container(keyedBy: CodingKeys.self)
//        type = try values.decode(String.self, forKey: .type)
//        content = try values.decode(AnyCodable.self, forKey: .content)
//        contentType = try values.decode(String.self, forKey: .contentType)
//        expiryDate = try values.decode(Date.self, forKey: .expiryDate)
//        meta = try? values.decode([String: AnyCodable].self, forKey: .meta)
//    }
//
//    func encode(to encoder: Encoder) throws {
//        var container = encoder.container(keyedBy: CodingKeys.self)
//        try container.encode(type, forKey: .type)
//        try container.encode(content, forKey: .content)
//        try container.encode(contentType, forKey: .contentType)
//        try container.encode(expiryDate, forKey: .expiryDate)
//        try container.encode(meta, forKey: .meta)
//    }
}
