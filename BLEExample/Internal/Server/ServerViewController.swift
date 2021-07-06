//
//  ServerViewController.swift
//  BLE Server
//
//  Created by Kirill Sidorov on 08.06.2021.
//

import UIKit

class ServerViewController: UIViewController, BLEServerDelegate {
    private let server = BLEServer()
    
    @IBOutlet private var label: UILabel!

    override func viewDidLoad() {
        super.viewDidLoad()
        label.text = "---"
        server.delegate = self
    }
    
    func didReceiveMessage(_ text: String) {
        server.setReadyToReceive(false)
        label.text = text
        // Показываем текст 5 секунд, после чего снова разрешаем
        // отправку нам сообщений.
        DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(5)) { [self] in
            label.text = "---"
            server.setReadyToReceive(true)
        }
    }
}

