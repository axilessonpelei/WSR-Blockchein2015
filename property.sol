// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

contract PropertyContract {
    struct Property {
        uint256 propertyId;
        address owner;
        bool propertyType; // тип объекта (жилой/нежилой)
        uint256 serviceLife; // срок эксплуатации
        bool forSale;
        bool deposit;
        bool gifted;
        uint256 area; // площадь недвижимости
    }

    struct Sale {
        uint256 propertyId;
        address buyer;
        uint256 price;
        uint256 timeAfter; // время, после которого продажа не актуальна
        uint256 originalServiceLife; // оригинальный срок эксплуатации
    }

    struct Gift {
        uint256 propertyId;
        address newOwner; // новый владелец
    }

    struct Deposit {
        uint256 propertyId;
        address pledgee;
        uint256 amount;
        uint256 depositPeriod; // срок залога
        uint256 beingPledged; // дата начала залога
        bool confirmed; // подтвержденный залог
        bool active; // активный залог
    }

    Property[] public properties;
    Sale[] public sales;
    Gift[] public gifts;
    Deposit[] public deposits;

    address private admin;

    modifier isAdmin() {
        require(admin == msg.sender, unicode"Только администратор");
        _;
    }

    modifier propertyAvailable(uint256 _propertyId) {
        Property memory property = properties[_propertyId];
        require(!property.forSale, unicode"Объект уже выставлен на продажу");
        require(!property.deposit, unicode"Объект находится в залоге");
        require(!property.gifted, unicode"Объект уже подарен");
        _;
    }

    modifier onlyOwner(uint256 _propertyId) {
        require(msg.sender == properties[_propertyId].owner, unicode"Вы не владелец");
        _;
    }

    // Добавление нового объекта недвижимости
    function addProperty(bool _propertyType,uint256 _serviceLife,uint256 _area) external isAdmin {
        properties.push(Property(properties.length, msg.sender, _propertyType, _serviceLife, false, false, false, _area));
    }

    // Создание предложения о продаже
    function createSale(uint256 _propertyId,uint256 _price,uint256 _timeAfter) external onlyOwner(_propertyId) propertyAvailable(_propertyId) {
        Property memory property = properties[_propertyId];
        property.forSale = true;
        sales.push(Sale(_propertyId, address(0), _price, block.timestamp + _timeAfter, property.serviceLife));
    }

    // Перевод средств покупателем
    function transferFunds(uint256 _saleId) external payable {
        Sale memory sale = sales[_saleId];
        require(sale.buyer == address(0), unicode"Покупатель уже назначен");
        require(msg.value >= sale.price, unicode"недостаточно средств");
        require(block.timestamp <= sale.timeAfter, unicode"Продажа истекла");
        require(msg.sender != properties[sale.propertyId].owner, unicode"Вы не можете купить свою недвижимость");
        
    }

    // Подтверждение продажи продавцом
    function confirmSale(uint256 _saleId) external {
        Sale memory sale = sales[_saleId];
        Property memory property = properties[sale.propertyId];
        require(sale.buyer != address(0), unicode"Покупатель не перевел средства");
        require(msg.sender == property.owner, unicode"Только владелец может подтвердить продажу");
        property.owner = sale.buyer;
        property.forSale = false;
        property.serviceLife += block.timestamp - sale.originalServiceLife;
        sale.buyer = msg.sender;
        payable(property.owner).transfer(sale.price); // Перевод средств продавцу
    }

    // Возврат средств покупателю, если продавец отказался от продажи
    function cancelSale(uint256 _saleId) external onlyOwner(sales[_saleId].propertyId) {
        Sale memory sale = sales[_saleId];
        Property memory property = properties[sale.propertyId];
        require(sale.buyer != address(0), unicode"Покупатель не перевел средства");
        payable(sale.buyer).transfer(sale.price); // Возврат средств покупателю
        property.forSale = false;
        property.serviceLife = sale.originalServiceLife; // Восстановление срока эксплуатации
    }

    // Возврат средств покупателю, если срок продажи истек и продавец не подтвердил
    function refundIfNotConfirmed(uint256 _saleId) external {
        Sale memory sale = sales[_saleId];
        Property memory property = properties[sale.propertyId];
        require(block.timestamp > sale.timeAfter, unicode"Срок продажи еще не истек");
        require(sale.buyer != address(0), unicode"Покупатель не перевел средства");
        payable(sale.buyer).transfer(sale.price); // Возврат средств покупателю
        property.forSale = false;
        property.serviceLife = sale.originalServiceLife; // Восстановление срока эксплуатации
    }

    // Создание дарения
    function createGift(uint256 _propertyId, address _newOwner) external onlyOwner(_propertyId) propertyAvailable(_propertyId) {
        require(_newOwner != address(0), unicode"Некорректный адрес нового владельца");
        Property memory property = properties[_propertyId];
        property.gifted = true;
        gifts.push(Gift(_propertyId, _newOwner));
    }

    // Подтверждение дарения новым владельцем
    function confirmGift(uint256 _giftId) external {
        Gift memory gift = gifts[_giftId];
        Property storage property = properties[gift.propertyId];
        require(gift.newOwner == msg.sender, unicode"Вы не указаны как новый владелец");
        property.owner = msg.sender;
        property.gifted = false; // Объект больше не находится в процессе дарения
    }

    // Отмена дарения
    function cancelGift(uint256 _giftId) external onlyOwner(gifts[_giftId].propertyId) {
        Gift memory gift = gifts[_giftId];
        Property memory property = properties[gift.propertyId];
        property.gifted = false; // Снятие статуса дарения
        gift.newOwner = address(0); // Обнуление нового владельца
    }

    // Создание предложения по залогу
    function createDepositOffer(
        uint256 _propertyId,
        uint256 _amount,
        uint256 _depositPeriod
    ) external onlyOwner(_propertyId) propertyAvailable(_propertyId) {
        Property memory property = properties[_propertyId];
        property.deposit = true;
        deposits.push(Deposit(_propertyId, address(0), _amount, _depositPeriod, 0, false, false));
    }

    // Взятие объекта в залог
    function takeInDeposit(uint256 _depositId) external payable {
        Deposit memory deposit = deposits[_depositId];
        require(deposit.pledgee == address(0), unicode"Залогодатель уже назначен");
        require(msg.value >= deposit.amount, unicode"Недостаточно средст");
        deposit.pledgee = msg.sender;
    }

    // Подтверждение залога собственником
    function confirmDeposit(uint256 _depositId) external onlyOwner(deposits[_depositId].propertyId) {
        Deposit memory deposit = deposits[_depositId];
        Property memory property = properties[deposit.propertyId];
        require(deposit.pledgee != address(0), unicode"Залогодатель не назначен");
        deposit.confirmed = true;
        deposit.beingPledged = block.timestamp;
        deposit.active = true;
        payable(property.owner).transfer(deposit.amount); // Перевод залоговой суммы собственнику
    }

    // Возврат средств при отмене залога, если залог еще не подтвержден
    function cancelDepositOffer(uint256 _depositId) external onlyOwner(deposits[_depositId].propertyId) {
        Deposit memory deposit = deposits[_depositId];
        require(!deposit.confirmed, unicode"Залог уже подтвержден");
        deposit.active = false;
        deposit.pledgee = address(0); // Обнуление залогодателя
    }

    // Погашение залога собственником
    function repayDeposit(uint256 _depositId) external payable onlyOwner(deposits[_depositId].propertyId) {
        Deposit memory deposit = deposits[_depositId];
        require(deposit.active, unicode"Залог не активен");
        require(msg.value >= deposit.amount, unicode"Недостаточно средств");
        deposit.active = false;
        payable(deposit.pledgee).transfer(deposit.amount); // Возврат суммы залогодателю
    }
    // Переход собственности в случае просрочки залога
    function forecloseDeposit(uint256 _depositId) external {
        Deposit memory deposit = deposits[_depositId];
        Property memory property = properties[deposit.propertyId];
        require(deposit.active, unicode"Залог не активен");
        require(block.timestamp >= deposit.beingPledged + deposit.depositPeriod, unicode"Срок залога еще не истек");
        property.owner = deposit.pledgee; // Переход права собственности залогодателю
        property.deposit = false;
        deposit.active = false;
    }

      function getAllPropertys() external view returns (Property[] memory) {
        return properties;
    }

     function getAllSale() external view returns (Sale[] memory) {
        return sales;
    }

      function getAllGifts() external view returns (Gift[] memory) {
        return gifts;
    }

     function getAllDeposit() external view returns (Deposit[] memory) {
        return deposits;
     }  
}