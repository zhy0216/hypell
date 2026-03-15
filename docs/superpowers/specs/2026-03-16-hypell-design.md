# Hypell: Hyperliquid 量化执行框架

**日期**: 2026-03-16
**语言**: Haskell
**构建工具**: Cabal
**架构**: Effectful Effect System

## 概述

Hypell 是一个用 Haskell 编写的 Hyperliquid 现货量化执行框架。框架提供 Hyperliquid REST/WebSocket API 封装、订单管理、算法下单、风控模块，策略通过 Typeclass 接口接入。

## 技术选型

| 决策 | 选择 | 理由 |
|------|------|------|
| Effect System | Effectful | 性能接近 ReaderT IO，Dynamic dispatch 支持 IO/Pure 双 interpreter |
| 构建工具 | Cabal | 社区主流，依赖管理成熟 |
| 交易类型 | 现货 (Spot) | 初期聚焦，后续可扩展至 Perps |
| API 交互 | WebSocket + REST | WS 实时行情推送，REST 下单/查询 |
| 策略接入 | Haskell Typeclass | 策略用 Haskell 编写，类型安全 |

## 核心 Effect 定义

框架定义 6 个 domain-specific effects，每个代表一个清晰职责边界，均使用 Dynamic dispatch：

### Exchange Effect

与 Hyperliquid 交易所交互，负责下单、撤单、查询。

```haskell
data Exchange :: Effect where
  PlaceOrder    :: OrderRequest -> Exchange m OrderResponse
  CancelOrder   :: CancelRequest -> Exchange m CancelResponse
  CancelAll     :: Exchange m ()
  GetOpenOrders :: Exchange m [Order]
```

### MarketData Effect

行情数据获取，封装 REST 查询和 WebSocket 订阅。

```haskell
data MarketData :: Effect where
  GetSpotMeta       :: MarketData m SpotMeta
  GetSpotAssetCtxs  :: MarketData m [SpotAssetCtx]
  GetOrderBook      :: Coin -> MarketData m OrderBook
  SubscribeTrades   :: Coin -> MarketData m (TBQueue Trade)
```

### Account Effect

账户状态查询。

```haskell
data Account :: Effect where
  GetBalances   :: Account m [TokenBalance]
  GetUserTrades :: Account m [UserTrade]
```

### RiskControl Effect

风控规则检查，支持运行时动态调整参数。

```haskell
data RiskControl :: Effect where
  CheckOrder       :: OrderRequest -> RiskControl m RiskResult
  GetRiskLimits    :: RiskControl m RiskLimits
  UpdateRiskLimits :: RiskLimits -> RiskControl m ()
```

### OrderManager Effect

订单生命周期管理。

```haskell
data OrderManager :: Effect where
  SubmitOrder   :: OrderRequest -> OrderManager m ManagedOrder
  TrackOrder    :: OrderId -> OrderManager m OrderStatus
  CancelManaged :: OrderId -> OrderManager m ()
```

### AlgoExec Effect

算法下单（TWAP、冰山单）。

```haskell
data AlgoExec :: Effect where
  RunTWAP    :: TWAPParams -> AlgoExec m AlgoHandle
  RunIceberg :: IcebergParams -> AlgoExec m AlgoHandle
  CancelAlgo :: AlgoHandle -> AlgoExec m ()
```

## 核心数据类型

### 币对与订单

```haskell
data Coin = SpotCoin Text  -- "PURR/USDC", "@107"

data Side = Buy | Sell

data TimeInForce = GTC | IOC | ALO

data OrderType
  = Limit { price :: Scientific, tif :: TimeInForce }
  | Market

data OrderRequest = OrderRequest
  { orCoin  :: Coin
  , orSide  :: Side
  , orSize  :: Scientific
  , orType  :: OrderType
  , orCloid :: Maybe ClientOrderId
  }

data OrderResponse
  = OrderResting OrderId
  | OrderFilled { filledSize :: Scientific, avgPrice :: Scientific }
  | OrderError Text

data CancelRequest
  = CancelById Coin OrderId
  | CancelByCloid Coin ClientOrderId
```

### 行情数据

```haskell
data OrderBook = OrderBook
  { obBids :: [(Scientific, Scientific)]
  , obAsks :: [(Scientific, Scientific)]
  , obTime :: UTCTime
  }

data Trade = Trade
  { trCoin :: Coin, trSide :: Side
  , trPrice :: Scientific, trSize :: Scientific
  , trTime :: UTCTime
  }

data SpotAssetCtx = SpotAssetCtx
  { sacCoin :: Coin, sacMarkPrice :: Scientific
  , sacMidPrice :: Scientific, sacDayVol :: Scientific
  , sacPrevPrice :: Scientific
  }
```

### 账户与风控

```haskell
data TokenBalance = TokenBalance
  { tbCoin :: Coin, tbTotal :: Scientific
  , tbHold :: Scientific, tbAvail :: Scientific
  }

data RiskLimits = RiskLimits
  { rlMaxOrderSize    :: Scientific
  , rlMaxPositionSize :: Map Coin Scientific
  , rlMaxDailyVolume  :: Scientific
  , rlCooldownMs      :: Int
  }

data RiskResult = RiskPass | RiskReject Text
```

### 算法下单参数

```haskell
data TWAPParams = TWAPParams
  { twCoin :: Coin, twSide :: Side
  , twTotalSize :: Scientific, twSlices :: Int
  , twIntervalMs :: Int
  }

data IcebergParams = IcebergParams
  { ibCoin :: Coin, ibSide :: Side
  , ibTotalSize :: Scientific, ibVisibleSize :: Scientific
  , ibLimitPrice :: Scientific
  }
```

## Strategy Typeclass 接口

策略通过实现 `Strategy` typeclass 接入框架。策略不直接调用 `Exchange` effect，而是输出 `TradeAction` 指令，由框架执行引擎统一处理，实现策略与执行的解耦。

```haskell
class Strategy s where
  strategyName :: s -> Text

  initStrategy
    :: (MarketData :> es, Account :> es, Log :> es)
    => s -> Eff es s

  onEvent
    :: (MarketData :> es, Account :> es, RiskControl :> es, Log :> es)
    => s -> MarketEvent -> Eff es (s, [TradeAction])

  onShutdown
    :: (OrderManager :> es, Log :> es)
    => s -> Eff es ()
```

### 市场事件与交易指令

```haskell
data MarketEvent
  = EventTrade Trade
  | EventOrderBookUpdate Coin OrderBook
  | EventOrderFill OrderId Scientific Scientific
  | EventOrderCancel OrderId
  | EventTimer UTCTime

data TradeAction
  = ActionPlace OrderRequest
  | ActionCancel CancelRequest
  | ActionCancelAll
  | ActionAlgoTWAP TWAPParams
  | ActionAlgoIceberg IcebergParams
  | ActionLog Text
```

## 执行引擎与并发架构

```
┌─────────────────────────────────────────────────────┐
│                    Engine (主线程)                     │
│  ┌───────────┐   ┌──────────┐   ┌───────────────┐  │
│  │ EventLoop │◄──│ EventBus │◄──│ WS Listener   │  │
│  │           │   │ (TBQueue) │◄──│ Order Tracker │  │
│  │ strategy  │   │          │◄──│ Timer         │  │
│  │ .onEvent  │   └──────────┘   └───────────────┘  │
│  └─────┬─────┘                                      │
│        │ [TradeAction]                              │
│        ▼                                            │
│  ┌───────────┐   ┌──────────┐   ┌───────────────┐  │
│  │ RiskGate  │──▶│ Executor │──▶│ REST Client   │  │
│  │ 风控检查   │   │ 执行分发  │   │ HTTP→Exchange │  │
│  └───────────┘   └────┬─────┘   └───────────────┘  │
│                       │                             │
│                       ▼                             │
│                 ┌───────────┐                       │
│                 │ AlgoEngine│                       │
│                 │ TWAP/冰山  │                       │
│                 └───────────┘                       │
└─────────────────────────────────────────────────────┘
```

### 运行时环境

```haskell
data EngineEnv = EngineEnv
  { eeConfig     :: Config
  , eeEventBus   :: TBQueue MarketEvent
  , eeHttpMgr    :: Manager
  , eeWsConn     :: TVar (Maybe Connection)
  , eeRiskLimits :: TVar RiskLimits
  , eePositions  :: TVar (Map Coin TokenBalance)
  , eeOpenOrders :: TVar (Map OrderId Order)
  , eeDailyStats :: TVar DailyStats
  }
```

### 并发模型

- **TBQueue 事件总线**：所有数据源（WS 行情、订单状态、定时器）向同一有界队列推送事件，主循环单线程消费
- **STM 共享状态**：仓位、活跃订单、风控参数用 `TVar` 包装，线程安全读写，支持运行时热更新
- **withAsync 结构化并发**：后台线程用 `withAsync` 管理，异常传播到主线程实现 fail-fast
- **WebSocket 自动重连**：断连后 3 秒重连，Hyperliquid 重连后发送 snapshot 补全数据

### 引擎生命周期

```haskell
runEngine :: Strategy s => Config -> s -> IO ()
runEngine cfg initialStrategy = runEff
  . runLog stdoutLogger
  . runRiskControl
  . runOrderManager
  . runAccount
  . runMarketData
  . runExchange cfg
  $ do
    env <- initEnv cfg
    withAsync (wsListenerLoop env) $ \ws ->
      withAsync (orderTrackerLoop env) $ \ot ->
        withAsync (timerLoop env 1000) $ \tm ->
          eventLoop env initialStrategy
```

### 指令执行分发

```haskell
executeAction env = \case
  ActionPlace req -> do
    riskResult <- checkOrder req
    case riskResult of
      RiskPass     -> void $ submitOrder req
      RiskReject r -> log $ "Risk rejected: " <> r
  ActionCancel req   -> void $ send (CancelOrder req)
  ActionCancelAll    -> send CancelAll
  ActionAlgoTWAP p   -> void $ runTWAP p
  ActionAlgoIceberg p -> void $ runIceberg p
  ActionLog msg      -> log msg
```

## Interpreter 实现

每个 effect 提供 IO interpreter（生产）和 Pure interpreter（测试）。

### IO Interpreter 要点

- `runExchangeIO`: 通过 `Api.Rest` 发送签名的 POST 请求到 `/exchange`
- `runMarketDataIO`: REST 查询 + WebSocket 订阅注册
- `runRiskControlIO`: 从 `TVar` 读取风控参数和统计数据，调用纯函数 `evaluateRisk`
- `runAccountIO`: REST 查询 `/info` 获取余额

### Pure Interpreter 要点

- `runExchangePure`: 基于 `State MockExchangeState`，模拟订单簿
- `runMarketDataPure`: 基于 `State` 返回预设行情数据
- `runRiskControlPure`: 基于 `State RiskLimits`

### 风控核心（纯函数）

```haskell
evaluateRisk :: RiskLimits -> DailyStats -> Map Coin TokenBalance -> OrderRequest -> RiskResult
```

检查规则：单笔大小限制、持仓上限、日交易量上限。纯函数可直接单元测试。

## 测试策略

| 层级 | 内容 | 方法 |
|------|------|------|
| 单元测试 | `evaluateRisk`、JSON roundtrip、策略状态转换 | 纯函数 + `@?=` |
| 集成测试 | 策略 + 执行流程 | Pure interpreter + `runPureEff` |
| 端到端测试 | 完整下单/撤单流程 | Hyperliquid testnet |

## 项目结构

```
Users/yang/hypell/
├── Users/yang/hypell.cabal
├── app/Main.hs
├── src/Hypell/
│   ├── Types.hs              -- 核心数据类型
│   ├── Config.hs             -- 配置加载
│   ├── Effect/               -- Effect GADT 定义
│   │   ├── Exchange.hs
│   │   ├── MarketData.hs
│   │   ├── Account.hs
│   │   ├── RiskControl.hs
│   │   ├── OrderManager.hs
│   │   └── AlgoExec.hs
│   ├── Interpreter/          -- IO/Pure interpreter
│   │   ├── Exchange/{IO,Pure}.hs
│   │   ├── MarketData/{IO,Pure}.hs
│   │   ├── Account/{IO,Pure}.hs
│   │   ├── RiskControl.hs
│   │   ├── OrderManager.hs
│   │   └── AlgoExec.hs
│   ├── Api/                  -- Hyperliquid 协议封装
│   │   ├── Rest.hs
│   │   ├── WebSocket.hs
│   │   └── Signing.hs
│   ├── Engine.hs             -- 执行引擎
│   ├── Risk.hs               -- 风控纯函数
│   ├── Algo/{TWAP,Iceberg}.hs
│   └── Strategy.hs           -- Strategy typeclass
├── test/
│   ├── Test/Hypell/
│   │   ├── RiskTest.hs
│   │   ├── TypesTest.hs
│   │   ├── StrategyTest.hs
│   │   └── AlgoTest.hs
│   └── Spec.hs
├── config/example.yaml
└── strategies/SimpleGrid.hs
```

## 核心依赖

- **Effect System**: effectful-core, effectful-th
- **JSON**: aeson
- **HTTP**: http-client, http-client-tls
- **WebSocket**: websockets, wuss
- **签名**: crypton, memory
- **精度**: scientific
- **并发**: stm, async
- **配置**: yaml, optparse-applicative
- **日志**: co-log-core
- **测试**: tasty, tasty-hunit, tasty-quickcheck, QuickCheck

## Hyperliquid API 参考

- REST 端点: `POST /exchange`（下单/撤单）、`POST /info`（查询）
- WebSocket: `wss://api.hyperliquid.xyz/ws`（实时行情）
- Spot 资产标识: `10000 + index`（下单时）、`PURR/USDC` 或 `@{index}`（查询时）
- 签名: EIP-712 typed data，nonce 为毫秒时间戳
- Testnet: `https://api.hyperliquid-testnet.xyz`
