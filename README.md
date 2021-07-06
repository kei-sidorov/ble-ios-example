# Демо приложение

Это демо приложение для [конспекта о CoreBluetooth](https://sidorov.tech/all/bluetooth-ios/) написакнного по мотивам доклада «Работаем с Bluetooth в iOS» расказанного на пятом сезоне [Podlodka iOS Crew](https://podlodka.io/crew). 

# Что внутри

Внутри одно приложение сразу для двух ролей — клиента и сервера. С комменатриями к коду на русском языке.

## Сервер

Сервер ожидает отправленного клиентом сообщения и показывает его на экране в течении 5 секунд. Во время показа сообщения и при уходе в бекграунд сообщает клиентам о том, что пока не готов принимать новые сообщения. 

## Клиент

Ищет BLE устройство реализующее импровизированный сервис 5ти секундного показа сообщений и подключается к первому найденому серверу. Отображает имя устройства и следит за состоянием сервера, если тот не гттов принимать сообщения, то блокирует элементы управления.