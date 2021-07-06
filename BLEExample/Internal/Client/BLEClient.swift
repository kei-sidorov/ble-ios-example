//
//  BLEClient.swift
//  BLE Client
//
//  Created by Kirill Sidorov on 08.06.2021.
//

import Foundation
import CoreBluetooth

protocol BLEClientDelegate: AnyObject {
    func didConnect(to: String)
    func didDisconnect()
    func didChangedReadyToReceiveStatus(to: Bool)
}

class BLEClient: NSObject {
    weak var delegate: BLEClientDelegate?
    
    private var manager: CBCentralManager!
    
    // Мы обязаны держать ссылку на подключенное устройство
    // Иначе объект высвободиться из памяти и вызовет отключение
    private var peripheral: CBPeripheral?
    
    // Чтобы не каждый раз не искать характеристики в сервисах
    // сразу сохраним их в удобном для доступа словаре
    private var characteristics: [Characteristic: CBCharacteristic] = [:]
    
    // Статус подключения
    var isConnected: Bool {
        guard let peripheral = peripheral else { return false }
        return peripheral.state == .connected
    }
    
    override init() {
        super.init()
        // Шаг 1. Инициализируем сервис, передав делегат.
        // Если не указывать очередь — по умолчанию будет главная.
        manager = CBCentralManager(delegate: self, queue: nil)
    }
    
    // Главный внешний метод — метод отправки сообщений
    func send(message: String) {
        guard let peripheral = peripheral,
              let characteristic = characteristics[.message] 
        else { return }
        
        // Энкодируем данные в Data
        guard let data = message.data(using: .utf8) else { return }
        
        // Записываем изпользуя метод CBPeripheral
        peripheral.writeValue(data, for: characteristic, type: .withResponse)
    }
    
    // Метод для запуска сканирования.
    private func startScanning() {
        // Из опций используем одну — включаем фильтрацию дублей
        // Если не установить эту опцию, метод делегата `...didDiscover...`
        // будет срабатывать на каждый найденый Advertisement, а если установить
        // то только один раз для уникального устройства.
        let options: [String: Any] = [
            CBCentralManagerScanOptionAllowDuplicatesKey: false
        ]
        
        // Запускаем сканирование и устанавливаем дополнительную фильтрацию
        // по UUID сервиса. Метод делегата `...didDiscover...` будет срабатывать
        // только если будет обнаружено устройство, реализующее этот сервис.
        manager.scanForPeripherals(
            withServices: [Constants.UUID.Service.messaging], 
            options: options
        )
    }
    
    // Метод принудительного отключения
    private func disconnect() {
        guard let peripheral = peripheral else { return }
        self.peripheral = nil
        characteristics = [:]
        delegate?.didDisconnect()
        manager.cancelPeripheralConnection(peripheral)
    }
    
    // Метод чтения/подписки на характеристики
    private func initialReadCharacteristics() {
        guard let peripheral = peripheral else { return }
        
        // Метод `readValue(for:)` отправляет запросы на чтение
        // Ответ придет асинхронно в метод делегата `...didUpdateValueFor...`
        
        if let infoCharacteristic = characteristics[.info] {
            peripheral.readValue(for: infoCharacteristic)
        }
        
        if let readyToReceiveCharacteristic = characteristics[.readyToReceive] {
            peripheral.readValue(for: readyToReceiveCharacteristic)
            peripheral.setNotifyValue(true, for: readyToReceiveCharacteristic)
        }
    }
    
    // Метод для декодинга информации об устройстве из Data
    private func handleDeviceInfo(rawData: Data?) {
        // Мы ожидаем строку в UTF8
        guard let data = rawData,
              let deviceModel = String(data: data, encoding: .utf8) 
        else { return }
        delegate?.didConnect(to: deviceModel)
    }
    
    // Метод для декодинга информации о возможности  из Data
    private func handleReadyToReceiveValue(rawData: Data?) {
        // Мы ожидаем что когда устройство будет готово принять
        // следующие сообщение — оно запишет 1 (единицу) в
        // соответствующую характеристику.
        guard let data = rawData else { return }
        let status = data[0] == UInt8(1)
        delegate?.didChangedReadyToReceiveStatus(to: status)
    }
}

extension BLEClient: CBCentralManagerDelegate {
    // Важно запускать сканирование в состоянии `poweredOn`
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
            case .poweredOn:
                startScanning()
            default:
                disconnect()
                if central.isScanning {
                    central.stopScan()
                }
        }
    }
    
    // Метод будет срабатывать каждый раз когда будет найдено подходящее устройство.
    // см. метод `startScanning()` для опредения критериев поиска.
    func centralManager(
        _ central: CBCentralManager, 
        didDiscover peripheral: CBPeripheral, 
        advertisementData: [String : Any], 
        rssi RSSI: NSNumber
    ) {
        // Будем подключаться к первому попавшемуся устройству, которое реализует сервис
        central.stopScan()
        // Обязательно сохраняем сильную ссылку на объект периферийного устройства
        // перед подключением. Без этого объект высвободиться
        // из памяти и произойдет отмена подключения.
        self.peripheral = peripheral
        // Просим менеджер подключиться
        central.connect(peripheral, options: nil)
    }
    
    // Метод будет срабатывать успешное подключение к периферийному устройству
    func centralManager(
        _ central: CBCentralManager, 
        didConnect peripheral: CBPeripheral
    ) {
        // Дальнейшая работа предполагается с самим объектом CBPeripheral
        // и его делегатом. Назначим делегатом себя и попросим найти
        // интересующий нас сервис:
        self.peripheral?.delegate = self
        peripheral.discoverServices([Constants.UUID.Service.messaging])
    }
}

extension BLEClient: CBPeripheralDelegate {
    // При работе с другим устройством Apple, в случае если на стороне сервера
    // приложение будет выгружено или уйдет в бекраунд, мы не получим события дисконнекта.
    // Это логично — мы подключились к другому устройству (iPhone, iPad, Mac, etc.),
    // а не к программе. На этом устройстве есть еще с десяток системных сервисов.
    // Поэтому, если серверное приложение выгрузиться или уйдет в фон, мы получим уведомления
    // о том, что список сервисов изменился в метод делегата `...didModifyServices...`
    //
    // При работе с другими гаджетами этот метод будет вызываться только если
    // это предусмотрено его прошивкой, а при перезагрузке его ПО получим честный дисконнект.
    func peripheral(
        _ peripheral: CBPeripheral, 
        didModifyServices invalidatedServices: [CBService]
    ) {
        // Если среди сервисов, которые «исчезли» с удаленного устройства, пропал наш,
        // это сигнализирует о том, что программа на серверной стороне была закрыта или ушла
        // в фон. Отключимся и снова запустим поиск.
        if invalidatedServices.contains(where: { $0.uuid == Constants.UUID.Service.messaging }) {
            disconnect()
            startScanning()
        }
    }
    
    // Метод сработает когда найдутся сервисы, запрошенные при подключении к устройству.
    // См. метод `...didConnect...` выше у делегата CBCentralManager.
    func peripheral(
        _ peripheral: CBPeripheral, 
        didDiscoverServices error: Error?
    ) {
        peripheral.services?.forEach { service in
            // Для каждого сервиса запустим поиск всех характеристик
            peripheral.discoverCharacteristics(nil, for: service)
        }
    }
    
    // Метод сработает для каждого сервиса, как только будут найдены
    // запрошенные в нем характеристики.
    func peripheral(
        _ peripheral: CBPeripheral, 
        didDiscoverCharacteristicsFor service: CBService, 
        error: Error?
    ) {
        guard service.uuid == Constants.UUID.Service.messaging,
              let characteristics = service.characteristics 
        else { return }
        
        // Сохраним известные нам характеристики в словаре
        // для удобного обращения в будущем
        for characteristic in characteristics {
            guard let key = Characteristic(fromUUID: characteristic.uuid)
            else { continue }
            
            self.characteristics[key] = characteristic
        }
        
        // Сразу считаем начальные значения
        initialReadCharacteristics()
    }
    
    // Метод будет срабатывать каждый раз, как сервер ответит на запрос чтения или
    // решит уведомить об изменении notify характеристики.
    func peripheral(
        _ peripheral: CBPeripheral,
        didUpdateValueFor characteristic: CBCharacteristic, 
        error: Error?
    ) {
        // Определим источник информации и применим соотвествующий хендлер
        guard let characteristicID = Characteristic(fromUUID: characteristic.uuid) else { return }
        switch characteristicID {
            case .info:
                handleDeviceInfo(rawData: characteristic.value)
            case .readyToReceive:
                handleReadyToReceiveValue(rawData: characteristic.value)
            default:
                break
        }
    }
}

private extension Characteristic {
    init?(fromUUID uuid: CBUUID) {
        switch uuid {
            case Constants.UUID.Characteristic.info:
                self = .info
            case Constants.UUID.Characteristic.message:
                self = .message
            case Constants.UUID.Characteristic.readyToReceive:
                self = .readyToReceive
            default:
                return nil
        }
    }
}
