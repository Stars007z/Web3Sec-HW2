# Web3Sec-HW2: TripFund

ДЗ №2, сбор на поездку команды (базовый вариант + бонус V2).

- `src/TripFund.sol` - основной контракт
- `src/upgradeable/TripFundV1.sol` - версия для Transparent Proxy
- `src/upgradeable/TripFundV2.sol` - V2 с `contributeFor`
- `test/TripFund.t.sol` - тесты основной части
- `test/TripFundUpgrade.t.sol` - тесты бонуса (прокси и обновление V1 -> V2)
- `test/mocks/TestToken.sol` - тестовый токен на OpenZeppelin ERC20

## Версии

- Foundry 1.8.5
- Solidity 0.8.30
- forge-std 1.17.0
- OpenZeppelin Contracts / Contracts Upgradeable 5.7.0
- OpenZeppelin Foundry Upgrades 0.4.2
- Node.js 18+ (для тестов бонуса)

## Установка

Foundry: https://getfoundry.sh/introduction/installation (на macOS `brew install foundry`).

```bash
git clone --recursive https://github.com/Stars007z/Web3Sec-HW2.git
cd Web3Sec-HW2
```

Если клонировали без `--recursive`:

```bash
git submodule update --init --recursive
```

## Запуск

```bash
forge build
forge test
```

Тесты бонуса проверяют хранилище через openzeppelin-foundry-upgrades, он запускает `npx @openzeppelin/upgrades-core`, поэтому нужен Node.js (при первом запуске пакет скачивается из npm). Можно запустить тесты только основной части: `forge test --match-contract TripFundTest`.

## Пример approve + взнос

Сначала approve у токена на адрес TripFund, потом `contribute`:

```solidity
token.approve(address(fund), 100e18);
fund.contribute(100e18);
```

То же через anvil и cast. Запустить `anvil`, затем в другом терминале:

```bash
export RPC=http://127.0.0.1:8545
export ME=0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266

forge create test/mocks/TestToken.sol:TestToken --rpc-url $RPC --unlocked --from $ME --broadcast
export TOKEN=<адрес токена>

forge create src/TripFund.sol:TripFund --rpc-url $RPC --unlocked --from $ME --broadcast \
  --constructor-args $TOKEN $ME 1000ether $(( $(date +%s) + 7*24*60*60 ))
export FUND=<адрес TripFund>

cast send $TOKEN "mint(address,uint256)" $ME 1000ether --rpc-url $RPC --unlocked --from $ME
cast send $TOKEN "approve(address,uint256)" $FUND 100ether --rpc-url $RPC --unlocked --from $ME
cast send $FUND "contribute(uint256)" 100ether --rpc-url $RPC --unlocked --from $ME

cast call $FUND "contributions(address)(uint256)" $ME --rpc-url $RPC
cast call $FUND "totalRaised()(uint256)" --rpc-url $RPC
```

В бонусе approve делается на адрес прокси, все вызовы идут через прокси.
