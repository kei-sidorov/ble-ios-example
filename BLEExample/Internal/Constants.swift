//
//  Constants.swift
//  BLEExample
//
//  Created by Кирилл Сидоров on 06.07.2021.
//

import CoreBluetooth

struct Constants {
    struct UUID {
        struct Service {
            static let messaging = CBUUID(string: "92EC9B0C-DC90-4FCB-8964-AD53C740E34E")
        }
        struct Characteristic {
            static let message = CBUUID(string: "8385B969-33EF-403E-BA17-ED86D0F8FF9C")
            static let info = CBUUID(string: "8F7ADFB1-E65F-4B0D-997F-480BC1D9E621")
            static let readyToReceive = CBUUID(string: "136DC021-86FA-4096-BDC5-E36544166249")
        }
    }
}

enum Characteristic {
    case message
    case info
    case readyToReceive
}
