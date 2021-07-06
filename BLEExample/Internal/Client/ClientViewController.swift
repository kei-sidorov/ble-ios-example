//
//  ClientViewController.swift
//  BLE Client
//
//  Created by Kirill Sidorov on 08.06.2021.
//

import UIKit

class ClientViewController: UIViewController {
    
    @IBOutlet private var button: UIButton!
    @IBOutlet private var textField: UITextField!
    @IBOutlet private var statusLabel: UILabel!
    
    private let client = BLEClient()
    
    private var canSendMessage: Bool = false {
        didSet {
            button.isEnabled = canSendMessage
            textField.isEnabled = canSendMessage
        }
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        
        statusLabel.text = "<disconnected>"
        canSendMessage = false
        client.delegate = self
    }

    @IBAction func send() {
        guard let text = textField.text else { return }
        client.send(message: text)
        textField.text = ""
    }
}

extension ClientViewController: BLEClientDelegate {
    func didDisconnect() {
        canSendMessage = false
        statusLabel.text = "<disconnected>"
    }
    
    func didChangedReadyToReceiveStatus(to readyToReceiveStatus: Bool) {
        canSendMessage = readyToReceiveStatus
    }
    
    func didConnect(to deviceDescription: String) {
        statusLabel.text = "<connected to \(deviceDescription)>"
    }
}
