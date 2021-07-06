//
//  BLEClient.swift
//  BLE Client
//
//  Created by Kirill Sidorov on 08.06.2021.
//

import UIKit
import CoreBluetooth


protocol BLEServerDelegate: AnyObject {
    func didReceiveMessage(_: String)
}

private struct Values {
    static let info = UIDevice.current.name.data(using: .utf8)
    
    struct ReadyToReceive {
        static let no = Data([0])
        static let yes = Data([1])
    }
}

class BLEServer: NSObject {
    weak var delegate: BLEServerDelegate?
    
    private var manager: CBPeripheralManager!
    private var characteristics: [Characteristic: CBMutableCharacteristic] = [:]
    
    override init() {
        super.init()
        // Первым делом создаём менеджер периферийного устройства.
        manager = CBPeripheralManager(delegate: self, queue: nil)
        
        // Установим обработчики входа/выхода в/из бекграунда
        // чтобы уведомить клиента о том, что мы пока не готовы
        // принимать сообщения.
        NotificationCenter.default.addObserver(
            self, 
            selector: #selector(appMovedToBackground), 
            name: UIApplication.willResignActiveNotification, 
            object: nil
        )
        NotificationCenter.default.addObserver(
            self, 
            selector: #selector(appMovedToForeground), 
            name: UIApplication.willEnterForegroundNotification, 
            object: nil
        )
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    // Метод для уведомления клиента о нашей возможности принять следующее сообщение.
    func setReadyToReceive(_ ready: Bool) {
        guard let characteristic = characteristics[.readyToReceive] else { return }
        let value = ready ? Values.ReadyToReceive.yes : Values.ReadyToReceive.no
        
        // Попросим менеджер оповестить клиентов, отслеживающих характеристику
        // `readyToReceive` о новом значении.
        manager.updateValue(
            value, 
            for: characteristic, 
            onSubscribedCentrals: nil
        )
        characteristic.value = value
    }
    
    // Метод сборки дерева сервисов и характеристик.
    private func buildServicesTree() {
        // Чистим сервисы, иначе при повторной регистрации можем получить креш.
        manager.removeAllServices()
        
        // Собираем наше мини дерево свойства и его характеристик,
        // Устанавливаем нужные свойства и права.
        let service = CBMutableService(
            type: Constants.UUID.Service.messaging, 
            primary: true
        )
        
        let infoCharacteristic = CBMutableCharacteristic(
            type: Constants.UUID.Characteristic.info, 
            properties: [.read], 
            value: Values.info,
            permissions: [.readable]
        )
        
        let readyToReceiveCharacteristic = CBMutableCharacteristic(
            type: Constants.UUID.Characteristic.readyToReceive, 
            properties: [.read, .notify], 
            value: nil, 
            permissions: [.readable]
        )
        
        let messageCharacteristic = CBMutableCharacteristic(
            type: Constants.UUID.Characteristic.message, 
            properties: [.write], 
            value: nil, 
            permissions: [.writeable]
        )
        
        // Сохраним для быстрого доступа
        characteristics = [
            .info: infoCharacteristic,
            .message: messageCharacteristic,
            .readyToReceive: readyToReceiveCharacteristic
        ]
        
        // Запишем в сервис
        service.characteristics = characteristics.map { $0.value }
        
        // А сервис зарегистрируем в менеджере
        manager.add(service)
    }
    
    // Метод обработки нового сообщения
    private func handleNewMessage(with data: Data?) {
        // Пока обрабатываем сообщение, уведомим клиента о нашей невозможности
        // принять еще одно.
        setReadyToReceive(false)
        
        // Мы ожидаем сообщение как строку в UTF8
        guard let data = data else { return }
        guard let message = String(data: data, encoding: .utf8) else { return }
        
        delegate?.didReceiveMessage(message)
    }
}

extension BLEServer {
    // Обработка событий входа в бекграунд и возвращения из него.
    @objc func appMovedToBackground() {
        setReadyToReceive(false)
    }
    
    @objc func appMovedToForeground() {
        setReadyToReceive(true)
    }
}

extension BLEServer: CBPeripheralManagerDelegate {
    // Метод будет срабатывать на каждое изменение состояния менеджера
    func peripheralManagerDidUpdateState(_ manager: CBPeripheralManager) {
        switch manager.state {
            case .poweredOn:
                // Если мы еще не собрали дерево сервисов и характеристик - соберем
                if characteristics.isEmpty {
                    buildServicesTree()
                }
                // Начнем рассылку рекламных пакетов, и укажем в этом пакете что
                // реализуем сервис приема сообщений для того, чтобы
                // клиенты могли фильтровать устройства и найти нас быстрее.
                manager.startAdvertising(
                    [CBAdvertisementDataServiceUUIDsKey: [Constants.UUID.Service.messaging]]
                )
                // Укажем что уже готовы принимать новые сообщения
                setReadyToReceive(true)
            case .poweredOff:
                // Если Bluetooth выключили — завершим рассылку пакетов.
                manager.stopAdvertising()
            default:
                // В демо проекте все состояния не рассматриваются.
                print("unsupported state")
        }
    }
    
    // Метод будет срабатывать как только будут новые запросы на запись для нас
    // В нашем примере он будет один, но всё же код сделаем универсальным.
    // В кейсах с интенсивной отправкой, они могут копиться в массив и приходить чанками.
    func peripheralManager(
        _ manager: CBPeripheralManager, 
        didReceiveWrite requests: [CBATTRequest]
    ) {
        for request in requests {
            switch request.characteristic.uuid {
                case Constants.UUID.Characteristic.message:
                    // Если это характеристика сообщения, обработаем его
                    // и ответим «успехом»
                    handleNewMessage(with: request.value)
                    manager.respond(to: request, withResult: .success)
                default:
                    // У нас больше нет характеристик, доступных на запись, поэтому
                    // ответим что не можем принять запрос.
                    print("unknown characteristic")
                    manager.respond(to: request, withResult: .writeNotPermitted)
            }
        }
    }
    
    // Метод будет срабатывать каждый раз, как сервер получит запрос на чтение от клиента.
    func peripheralManager(_ peripheral: CBPeripheralManager, didReceiveRead request: CBATTRequest) {
        switch request.characteristic.uuid {
            case Constants.UUID.Characteristic.info:
                request.value = Values.info
                manager.respond(to: request, withResult: .success)
            case Constants.UUID.Characteristic.readyToReceive:
                guard let characteristic = characteristics[.readyToReceive] 
                else {
                    manager.respond(to: request, withResult: .unlikelyError)
                    return
                }
                request.value = characteristic.value
                manager.respond(to: request, withResult: .success)
            default:
                manager.respond(to: request, withResult: .readNotPermitted)
        }
    }
}
