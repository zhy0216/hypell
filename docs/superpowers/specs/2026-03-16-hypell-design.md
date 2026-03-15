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
  SubscribeTrades   :: Coin -> MarketData m ()  -- 注册订阅，事件通过 EventBus 投递
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

订单生命周期管理。`OrderManager` 是 `Exchange` 之上的高层 effect：`runOrderManagerIO` 内部调用 `Exchange` effect 执行下单/撤单，同时维护 `EngineEnv.eeOpenOrders` 的 `TVar` 状态。WS listener 也会更新该 `TVar`（通过推送 `EventOrderFill`/`EventOrderCancel` 事件）。

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

### Log Effect

日志通过 Static dispatch 封装 `co-log-core` 的 `LogAction`。定义如下：

```haskell
data Log :: Effect
type instance DispatchOf Log = Static WithSideEffects
newtype instance StaticRep Log = Log (LogAction IO Text)

log :: Log :> es => Text -> Eff es ()
log msg = do
  Log action <- getStaticRep
  unsafeEff_ $ unLogAction action msg

runLog :: IOE :> es => LogAction IO Text -> Eff (Log : es) a -> Eff es a
runLog action = evalStaticRep (Log action)

data LogLevel = Debug | Info | Warn | Error
  deriving (Eq, Ord, Show)
-- LogLevel 用于 Config.cfgLogLevel 过滤日志级别
```

## 核心数据类型

### 基础标识类型

```haskell
type OrderId = Word64          -- Hyperliquid 返回的数字订单 ID
type ClientOrderId = Text      -- 客户端自定义订单 ID (cloid)，hex 格式
```

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

data CancelResponse
  = CancelSuccess
  | CancelError Text            -- "Order was never placed, already canceled, or filled"

-- Order: 活跃订单的完整表示，存储在 eeOpenOrders 中
data Order = Order
  { oId        :: OrderId
  , oRequest   :: OrderRequest
  , oStatus    :: OrderStatus
  , oFilledSz  :: Scientific    -- 已成交量
  , oAvgPrice  :: Maybe Scientific
  , oCreatedAt :: UTCTime
  }
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

-- SpotMeta: 现货市场元数据
data SpotMeta = SpotMeta
  { smTokens   :: [TokenInfo]
  , smUniverse :: [SpotPair]
  }

data TokenInfo = TokenInfo
  { tiName    :: Text
  , tiIndex   :: Int
  , tiTokenId :: Text
  , tiDecimals :: Int
  }

data SpotPair = SpotPair
  { spName       :: Text          -- "PURR/USDC"
  , spBaseToken  :: Int           -- token index
  , spQuoteToken :: Int
  , spIndex      :: Int           -- universe index
  }

-- UserTrade: 用户历史成交记录
data UserTrade = UserTrade
  { utCoin      :: Coin
  , utSide      :: Side
  , utPrice     :: Scientific
  , utSize      :: Scientific
  , utFee       :: Scientific
  , utTime      :: UTCTime
  , utOrderId   :: OrderId
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

### 引擎辅助类型

```haskell
-- Config: 从 YAML + 环境变量加载
data Config = Config
  { cfgNetwork    :: Network          -- Testnet | Mainnet
  , cfgApiUrl     :: Text             -- "https://api.hyperliquid.xyz"
  , cfgWsUrl      :: Text             -- "wss://api.hyperliquid.xyz/ws"
  , cfgPrivateKey :: ByteString       -- 从 HYPELL_PRIVATE_KEY 环境变量读取
  , cfgRisk       :: RiskLimits       -- 初始风控参数
  , cfgEngine     :: EngineConfig     -- 引擎参数
  , cfgLogLevel   :: LogLevel         -- Debug | Info | Warn | Error
  }

data Network = Testnet | Mainnet

data EngineConfig = EngineConfig
  { ecEventQueueSize      :: Int      -- 事件总线容量，默认 4096
  , ecOrderPollIntervalMs :: Int      -- 订单轮询间隔，默认 2000
  , ecHeartbeatIntervalMs :: Int      -- 心跳间隔，默认 1000
  }

-- ManagedOrder: OrderManager 返回的托管订单
data ManagedOrder = ManagedOrder
  { moId        :: OrderId
  , moRequest   :: OrderRequest
  , moStatus    :: OrderStatus
  , moCreatedAt :: UTCTime
  }

data OrderStatus
  = OsResting                         -- 挂单中
  | OsPartialFill Scientific          -- 部分成交(已成交量)
  | OsFilled Scientific Scientific    -- 全部成交(总量, 均价)
  | OsCancelled
  | OsRejected Text

-- DailyStats: 当日累计统计，用于风控
data DailyStats = DailyStats
  { dsTotalVolume   :: Scientific     -- 当日累计交易量
  , dsTotalTrades   :: Int            -- 当日交易笔数
  , dsLastOrderTime :: Maybe UTCTime  -- 上次下单时间(用于冷却期)
  , dsDate          :: Day            -- 统计日期，跨日自动重置
  }

-- AlgoHandle: 算法执行句柄
data AlgoHandle = AlgoHandle
  { ahId     :: Text                  -- 唯一标识
  , ahThread :: Async ()              -- 执行线程
  , ahParams :: AlgoParams            -- 原始参数
  , ahStatus :: TVar AlgoStatus       -- 实时状态
  }

data AlgoParams = AlgoTWAP TWAPParams | AlgoIceberg IcebergParams

data AlgoStatus
  = AlgoRunning Scientific            -- 已执行量
  | AlgoCompleted Scientific          -- 最终执行量
  | AlgoCancelled
  | AlgoFailed Text
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
    :: (MarketData :> es, Account :> es, Log :> es)
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
- **WebSocket 自动重连**：断连后指数退避重连（初始 1 秒，最大 30 秒，乘数 2x），最多重试 20 次后放弃并通知策略 `onShutdown`。重连期间 `TradeAction` 会因 `Exchange` effect 失败而被 RiskGate 拦截记录。Hyperliquid 重连后发送 snapshot 补全数据

### 后台线程说明

- **wsListenerLoop**: 维护 WebSocket 连接，解析推送消息并归一化为 `MarketEvent`（`EventTrade`、`EventOrderBookUpdate`）写入 EventBus。处理断连重连和重新订阅
- **orderTrackerLoop**: 每 `ecOrderPollIntervalMs` 毫秒通过 REST `/info` 查询用户活跃订单，与 `eeOpenOrders` TVar 对比，检测新成交和撤单，生成 `EventOrderFill` / `EventOrderCancel` 事件写入 EventBus
- **timerLoop**: 每 `ecHeartbeatIntervalMs` 毫秒向 EventBus 写入 `EventTimer`，供策略做定时逻辑

### 引擎生命周期

```haskell
runEngine :: Strategy s => Config -> s -> IO ()
runEngine cfg initialStrategy = runEff
  . runLog (mkLogAction cfg)
  . runRiskControlIO env
  . runOrderManagerIO env
  . runAccountIO env
  . runMarketDataIO env
  . runExchangeIO env
  $ do
    env <- initEnv cfg
    withAsync (wsListenerLoop env) $ \ws ->
      withAsync (orderTrackerLoop env) $ \ot ->
        withAsync (timerLoop env 1000) $ \tm ->
          eventLoop env initialStrategy
```

注：`runEngine` 中的 `run*IO` 后缀与 IO interpreter 命名一致。实际实现中 `env` 需在 effect stack 之外初始化（通过 `bracket` 模式），此处为简化展示。

### initEnv

```haskell
initEnv :: Config -> IO EngineEnv
```

`initEnv` 职责：
1. 创建 `http-client-tls` 的 TLS `Manager`
2. 初始化所有 `TVar`：`eeRiskLimits`（从 `cfgRisk`）、`eePositions`（空 Map）、`eeOpenOrders`（空 Map）、`eeDailyStats`（零值，当天日期）、`eeWsConn`（Nothing）
3. 创建 `TBQueue` 事件总线（容量为 `ecEventQueueSize`）
4. 不执行任何 REST 调用（行情初始化由 `wsListenerLoop` 的首次 snapshot 完成）

### 指令执行分发

```haskell
executeAction
  :: ( Exchange :> es, RiskControl :> es, OrderManager :> es
     , AlgoExec :> es, Log :> es, IOE :> es )
  => EngineEnv -> TradeAction -> Eff es ()
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
- `runMarketDataIO`: REST 查询 + WS 订阅注册（`SubscribeTrades` 向 WS listener 注册 coin，事件通过 EventBus 投递）
- `runRiskControlIO`: 从 `TVar` 读取风控参数和统计数据，调用纯函数 `evaluateRisk`
- `runAccountIO`: REST 查询 `/info` 获取余额
- `runOrderManagerIO`: 内部调用 `Exchange` effect 执行下单/撤单，同步更新 `eeOpenOrders` TVar
- `runAlgoExecIO`: 为每个算法创建独立 `Async` 线程，TWAP 线程按间隔循环下单，Iceberg 线程监听成交后补单，线程引用存入 `AlgoHandle`

### Pure Interpreter 要点

- `runExchangePure`: 基于 `State MockExchangeState`，模拟订单簿
- `runMarketDataPure`: 基于 `State` 返回预设行情数据
- `runAccountPure`: 基于 `State [TokenBalance]` 返回预设余额
- `runRiskControlPure`: 基于 `State RiskLimits`
- `runOrderManagerPure`: 基于 `State (Map OrderId ManagedOrder)`，内部调用 `Exchange` effect（使用 `runExchangePure`）
- `runAlgoExecPure`: 立即返回模拟的 `AlgoHandle`，不创建线程

### 风控核心（纯函数）

```haskell
evaluateRisk :: RiskLimits -> DailyStats -> Map Coin TokenBalance -> OrderRequest -> RiskResult
```

检查规则：单笔大小限制、持仓上限、日交易量上限。纯函数可直接单元测试。

## 测试策略

| 层级 | 内容 | 方法 |
|------|------|------|
| 单元测试 | `evaluateRisk`、JSON roundtrip、策略状态转换 | 纯函数 + `@?=` |
| 属性测试 | 风控不变量（超限订单必定拒绝）、算法参数校验 | QuickCheck property tests |
| 集成测试 | 策略 + 执行流程 | Pure interpreter + `runPureEff` |
| 端到端测试 | 完整下单/撤单流程 | Hyperliquid testnet |

## 项目结构

```
hypell/
├── hypell.cabal
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
└── examples/
    └── SimpleGrid.hs        -- 示例策略（独立可执行 cabal stanza）
```

`examples/SimpleGrid.hs` 在 cabal 中作为独立的 `executable` stanza 编译，依赖 `hypell` 库。

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
