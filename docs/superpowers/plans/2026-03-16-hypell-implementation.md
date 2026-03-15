# Hypell Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a Haskell execution framework for Hyperliquid spot trading using Effectful, with risk control, algo execution, and a Strategy typeclass interface.

**Architecture:** Bottom-up build: core types → effect definitions → pure interpreters + tests → API layer (REST/WS/Signing) → IO interpreters → engine + concurrency → algo execution → example strategy. Each layer compiles and is tested before the next.

**Tech Stack:** Haskell (GHC 9.6+), Cabal, Effectful, aeson, http-client-tls, websockets/wuss, crypton, STM, tasty

**Spec:** `docs/superpowers/specs/2026-03-16-hypell-design.md`

---

## Chunk 1: Project Scaffold + Core Types

### Task 1: Cabal project scaffold

**Files:**
- Create: `hypell.cabal`
- Create: `cabal.project`
- Create: `app/Main.hs`
- Create: `src/Hypell.hs`
- Create: `test/Spec.hs`
- Create: `config/example.yaml`

- [ ] **Step 1: Write `hypell.cabal`**

```cabal
cabal-version: 3.0
name:          hypell
version:       0.1.0.0
synopsis:      Hyperliquid spot trading execution framework
license:       MIT
build-type:    Simple

common common-deps
  default-language: GHC2021
  default-extensions:
    DataKinds
    GADTs
    TypeFamilies
    OverloadedStrings
    LambdaCase
    TemplateHaskell
    DeriveGeneric
    DerivingStrategies
    GeneralizedNewtypeDeriving
  ghc-options: -Wall -Wno-orphans
  build-depends:
      base >= 4.18 && < 5
    , text
    , bytestring
    , containers
    , stm
    , async
    , time
    , effectful-core >= 2.3
    , effectful-th
    , aeson
    , scientific
    , co-log-core

library
  import: common-deps
  hs-source-dirs: src
  exposed-modules:
      Hypell
    , Hypell.Types
    , Hypell.Config
    , Hypell.Effect.Log
    , Hypell.Effect.Exchange
    , Hypell.Effect.MarketData
    , Hypell.Effect.Account
    , Hypell.Effect.RiskControl
    , Hypell.Effect.OrderManager
    , Hypell.Effect.AlgoExec
    , Hypell.Risk
    , Hypell.Strategy
    , Hypell.Interpreter.Exchange.Pure
    , Hypell.Interpreter.MarketData.Pure
    , Hypell.Interpreter.Account.Pure
    , Hypell.Interpreter.RiskControl
    , Hypell.Interpreter.OrderManager
    , Hypell.Interpreter.AlgoExec
    , Hypell.Api.Rest
    , Hypell.Api.Signing
    , Hypell.Api.WebSocket
    , Hypell.Interpreter.Exchange.IO
    , Hypell.Interpreter.MarketData.IO
    , Hypell.Interpreter.Account.IO
    , Hypell.Engine
    , Hypell.Algo.TWAP
    , Hypell.Algo.Iceberg
  build-depends:
      http-client
    , http-client-tls
    , http-types
    , websockets
    , wuss
    , crypton
    , memory
    , yaml
    , optparse-applicative

test-suite hypell-test
  import: common-deps
  type: exitcode-stdio-1.0
  hs-source-dirs: test
  main-is: Spec.hs
  other-modules:
      Test.Hypell.TypesTest
    , Test.Hypell.RiskTest
    , Test.Hypell.StrategyTest
    , Test.Hypell.AlgoTest
  build-depends:
      hypell
    , tasty
    , tasty-hunit
    , tasty-quickcheck
    , QuickCheck

executable simple-grid
  import: common-deps
  hs-source-dirs: examples
  main-is: SimpleGrid.hs
  build-depends:
      hypell
```

- [ ] **Step 2: Write `cabal.project`**

```
packages: .
```

- [ ] **Step 3: Write stub `app/Main.hs`**

```haskell
module Main where

main :: IO ()
main = putStrLn "hypell: not yet implemented"
```

- [ ] **Step 4: Write stub `src/Hypell.hs`**

```haskell
module Hypell
  ( module Hypell.Types
  ) where

import Hypell.Types
```

- [ ] **Step 5: Write stub `test/Spec.hs`**

```haskell
import Test.Tasty

main :: IO ()
main = defaultMain $ testGroup "Hypell" []
```

- [ ] **Step 6: Write `config/example.yaml`**

```yaml
network: testnet
apiUrl: "https://api.hyperliquid-testnet.xyz"
wsUrl: "wss://api.hyperliquid-testnet.xyz/ws"

# Private key loaded from HYPELL_PRIVATE_KEY env var

risk:
  maxOrderSize: 1000
  maxDailyVolume: 50000
  cooldownMs: 500
  maxPositionSize:
    "HYPE/USDC": 5000
    "PURR/USDC": 10000

engine:
  eventQueueSize: 4096
  orderPollIntervalMs: 2000
  heartbeatIntervalMs: 1000

logging:
  level: info
```

- [ ] **Step 7: Verify scaffold compiles**

Run: `cabal build all --dry-run`
Expected: dependency resolution succeeds

- [ ] **Step 8: Commit**

```bash
git add -A
git commit -m "feat: initial cabal project scaffold"
```

---

### Task 2: Core types (`Types.hs`)

**Files:**
- Create: `src/Hypell/Types.hs`
- Create: `test/Test/Hypell/TypesTest.hs`

- [ ] **Step 1: Write JSON roundtrip tests for core types**

```haskell
module Test.Hypell.TypesTest (tests) where

import Test.Tasty
import Test.Tasty.HUnit
import Test.Tasty.QuickCheck
import Data.Aeson (encode, eitherDecode, ToJSON, FromJSON)
import Data.Scientific (scientific)
import Hypell.Types

roundtrip :: (Eq a, Show a, ToJSON a, FromJSON a) => a -> Assertion
roundtrip x = eitherDecode (encode x) @?= Right x

tests :: TestTree
tests = testGroup "Types"
  [ testCase "Coin roundtrip" $
      roundtrip (SpotCoin "PURR/USDC")
  , testCase "Side roundtrip" $
      roundtrip Buy
  , testCase "OrderRequest roundtrip" $
      roundtrip OrderRequest
        { orCoin  = SpotCoin "@107"
        , orSide  = Buy
        , orSize  = scientific 100 0
        , orType  = Limit (scientific 25 (-1)) GTC
        , orCloid = Nothing
        }
  , testCase "OrderResponse Resting roundtrip" $
      roundtrip (OrderResting 12345)
  , testCase "OrderResponse Filled roundtrip" $
      roundtrip (OrderFilled (scientific 50 0) (scientific 25 (-1)))
  , testCase "OrderResponse Error roundtrip" $
      roundtrip (OrderError "insufficient balance")
  , testCase "CancelResponse roundtrip" $
      roundtrip CancelSuccess
  , testCase "RiskLimits roundtrip" $
      roundtrip RiskLimits
        { rlMaxOrderSize    = scientific 1000 0
        , rlMaxPositionSize = mempty
        , rlMaxDailyVolume  = scientific 50000 0
        , rlCooldownMs      = 500
        }
  , testCase "SpotMeta roundtrip" $
      roundtrip SpotMeta
        { smTokens   = [TokenInfo "PURR" 0 "0xPURR" 8]
        , smUniverse = [SpotPair "PURR/USDC" 0 1 0]
        }
  ]
```

- [ ] **Step 2: Wire test into `test/Spec.hs`**

```haskell
import Test.Tasty
import qualified Test.Hypell.TypesTest

main :: IO ()
main = defaultMain $ testGroup "Hypell"
  [ Test.Hypell.TypesTest.tests
  ]
```

- [ ] **Step 3: Run tests to verify they fail**

Run: `cabal test`
Expected: FAIL — `Hypell.Types` module does not exist

- [ ] **Step 4: Implement `Types.hs` — identifier types and Coin**

```haskell
module Hypell.Types
  ( -- * Identifiers
    OrderId
  , ClientOrderId
    -- * Coin
  , Coin(..)
    -- * Side
  , Side(..)
    -- * Time in Force
  , TimeInForce(..)
    -- * Order types
  , OrderType(..)
  , OrderRequest(..)
  , OrderResponse(..)
  , CancelRequest(..)
  , CancelResponse(..)
  , Order(..)
  , OrderStatus(..)
    -- * Market data
  , OrderBook(..)
  , Trade(..)
  , SpotAssetCtx(..)
  , SpotMeta(..)
  , TokenInfo(..)
  , SpotPair(..)
    -- * Account
  , TokenBalance(..)
  , UserTrade(..)
    -- * Risk
  , RiskLimits(..)
  , RiskResult(..)
    -- * Algo
  , TWAPParams(..)
  , IcebergParams(..)
  , AlgoParams(..)
  , AlgoStatus(..)
    -- * Engine
  , MarketEvent(..)
  , TradeAction(..)
    -- * Config
  , LogLevel(..)
  , Network(..)
  , EngineConfig(..)
  , DailyStats(..)
  ) where

import Data.Aeson
import Data.Map.Strict (Map)
import Data.Scientific (Scientific)
import Data.Text (Text)
import Data.Time (UTCTime, Day)
import Data.Word (Word64)
import GHC.Generics (Generic)

-- === Identifiers ===

type OrderId = Word64
type ClientOrderId = Text

-- === Coin ===

newtype Coin = SpotCoin Text
  deriving stock (Eq, Ord, Show, Generic)
  deriving newtype (FromJSON, ToJSON, FromJSONKey, ToJSONKey)

-- === Side ===

data Side = Buy | Sell
  deriving stock (Eq, Show, Generic)

instance ToJSON Side where
  toJSON Buy  = String "B"
  toJSON Sell = String "A"

instance FromJSON Side where
  parseJSON = withText "Side" $ \case
    "B" -> pure Buy
    "A" -> pure Sell
    t   -> fail $ "Unknown side: " <> show t

-- === TimeInForce ===

data TimeInForce = GTC | IOC | ALO
  deriving stock (Eq, Show, Generic)
  deriving anyclass (ToJSON, FromJSON)

-- === OrderType ===

data OrderType
  = Limit { price :: Scientific, tif :: TimeInForce }
  | Market
  deriving stock (Eq, Show, Generic)
  deriving anyclass (ToJSON, FromJSON)

-- === OrderRequest ===

data OrderRequest = OrderRequest
  { orCoin  :: Coin
  , orSide  :: Side
  , orSize  :: Scientific
  , orType  :: OrderType
  , orCloid :: Maybe ClientOrderId
  } deriving stock (Eq, Show, Generic)
    deriving anyclass (ToJSON, FromJSON)

-- === OrderResponse ===

data OrderResponse
  = OrderResting OrderId
  | OrderFilled { filledSize :: Scientific, avgPrice :: Scientific }
  | OrderError Text
  deriving stock (Eq, Show, Generic)
  deriving anyclass (ToJSON, FromJSON)

-- === Cancel ===

data CancelRequest
  = CancelById Coin OrderId
  | CancelByCloid Coin ClientOrderId
  deriving stock (Eq, Show, Generic)
  deriving anyclass (ToJSON, FromJSON)

data CancelResponse
  = CancelSuccess
  | CancelError Text
  deriving stock (Eq, Show, Generic)
  deriving anyclass (ToJSON, FromJSON)

-- === Order ===

data OrderStatus
  = OsResting
  | OsPartialFill Scientific
  | OsFilled Scientific Scientific
  | OsCancelled
  | OsRejected Text
  deriving stock (Eq, Show, Generic)
  deriving anyclass (ToJSON, FromJSON)

data Order = Order
  { oId        :: OrderId
  , oRequest   :: OrderRequest
  , oStatus    :: OrderStatus
  , oFilledSz  :: Scientific
  , oAvgPrice  :: Maybe Scientific
  , oCreatedAt :: UTCTime
  } deriving stock (Eq, Show, Generic)
    deriving anyclass (ToJSON, FromJSON)

-- === Market Data ===

data OrderBook = OrderBook
  { obBids :: [(Scientific, Scientific)]
  , obAsks :: [(Scientific, Scientific)]
  , obTime :: UTCTime
  } deriving stock (Eq, Show, Generic)
    deriving anyclass (ToJSON, FromJSON)

data Trade = Trade
  { trCoin  :: Coin
  , trSide  :: Side
  , trPrice :: Scientific
  , trSize  :: Scientific
  , trTime  :: UTCTime
  } deriving stock (Eq, Show, Generic)
    deriving anyclass (ToJSON, FromJSON)

data SpotAssetCtx = SpotAssetCtx
  { sacCoin      :: Coin
  , sacMarkPrice :: Scientific
  , sacMidPrice  :: Scientific
  , sacDayVol    :: Scientific
  , sacPrevPrice :: Scientific
  } deriving stock (Eq, Show, Generic)
    deriving anyclass (ToJSON, FromJSON)

data SpotMeta = SpotMeta
  { smTokens   :: [TokenInfo]
  , smUniverse :: [SpotPair]
  } deriving stock (Eq, Show, Generic)
    deriving anyclass (ToJSON, FromJSON)

data TokenInfo = TokenInfo
  { tiName     :: Text
  , tiIndex    :: Int
  , tiTokenId  :: Text
  , tiDecimals :: Int
  } deriving stock (Eq, Show, Generic)
    deriving anyclass (ToJSON, FromJSON)

data SpotPair = SpotPair
  { spName       :: Text
  , spBaseToken  :: Int
  , spQuoteToken :: Int
  , spIndex      :: Int
  } deriving stock (Eq, Show, Generic)
    deriving anyclass (ToJSON, FromJSON)

-- === Account ===

data TokenBalance = TokenBalance
  { tbCoin  :: Coin
  , tbTotal :: Scientific
  , tbHold  :: Scientific
  , tbAvail :: Scientific
  } deriving stock (Eq, Show, Generic)
    deriving anyclass (ToJSON, FromJSON)

data UserTrade = UserTrade
  { utCoin    :: Coin
  , utSide    :: Side
  , utPrice   :: Scientific
  , utSize    :: Scientific
  , utFee     :: Scientific
  , utTime    :: UTCTime
  , utOrderId :: OrderId
  } deriving stock (Eq, Show, Generic)
    deriving anyclass (ToJSON, FromJSON)

-- === Risk ===

data RiskLimits = RiskLimits
  { rlMaxOrderSize    :: Scientific
  , rlMaxPositionSize :: Map Coin Scientific
  , rlMaxDailyVolume  :: Scientific
  , rlCooldownMs      :: Int
  } deriving stock (Eq, Show, Generic)
    deriving anyclass (ToJSON, FromJSON)

data RiskResult
  = RiskPass
  | RiskReject Text
  deriving stock (Eq, Show)

-- === Algo ===

data TWAPParams = TWAPParams
  { twCoin       :: Coin
  , twSide       :: Side
  , twTotalSize  :: Scientific
  , twSlices     :: Int
  , twIntervalMs :: Int
  } deriving stock (Eq, Show, Generic)
    deriving anyclass (ToJSON, FromJSON)

data IcebergParams = IcebergParams
  { ibCoin        :: Coin
  , ibSide        :: Side
  , ibTotalSize   :: Scientific
  , ibVisibleSize :: Scientific
  , ibLimitPrice  :: Scientific
  } deriving stock (Eq, Show, Generic)
    deriving anyclass (ToJSON, FromJSON)

data AlgoParams
  = AlgoTWAP TWAPParams
  | AlgoIceberg IcebergParams
  deriving stock (Eq, Show, Generic)
  deriving anyclass (ToJSON, FromJSON)

data AlgoStatus
  = AlgoRunning Scientific
  | AlgoCompleted Scientific
  | AlgoCancelled
  | AlgoFailed Text
  deriving stock (Eq, Show, Generic)
  deriving anyclass (ToJSON, FromJSON)

-- === Events & Actions ===

data MarketEvent
  = EventTrade Trade
  | EventOrderBookUpdate Coin OrderBook
  | EventOrderFill OrderId Scientific Scientific
  | EventOrderCancel OrderId
  | EventTimer UTCTime
  deriving stock (Eq, Show)

data TradeAction
  = ActionPlace OrderRequest
  | ActionCancel CancelRequest
  | ActionCancelAll
  | ActionAlgoTWAP TWAPParams
  | ActionAlgoIceberg IcebergParams
  | ActionLog Text
  deriving stock (Eq, Show)

-- === Config ===

data LogLevel = Debug | Info | Warn | Error
  deriving stock (Eq, Ord, Show, Generic)
  deriving anyclass (ToJSON, FromJSON)

data Network = Testnet | Mainnet
  deriving stock (Eq, Show, Generic)
  deriving anyclass (ToJSON, FromJSON)

data EngineConfig = EngineConfig
  { ecEventQueueSize      :: Int
  , ecOrderPollIntervalMs :: Int
  , ecHeartbeatIntervalMs :: Int
  } deriving stock (Eq, Show, Generic)
    deriving anyclass (ToJSON, FromJSON)

data DailyStats = DailyStats
  { dsTotalVolume   :: Scientific
  , dsTotalTrades   :: Int
  , dsLastOrderTime :: Maybe UTCTime
  , dsDate          :: Day
  } deriving stock (Eq, Show, Generic)
    deriving anyclass (ToJSON, FromJSON)
```

- [ ] **Step 5: Update `src/Hypell.hs` to re-export**

```haskell
module Hypell
  ( module Hypell.Types
  ) where

import Hypell.Types
```

- [ ] **Step 6: Run tests**

Run: `cabal test`
Expected: All TypesTest roundtrip tests PASS

- [ ] **Step 7: Commit**

```bash
git add src/Hypell/Types.hs src/Hypell.hs test/Spec.hs test/Test/Hypell/TypesTest.hs
git commit -m "feat: core types with JSON roundtrip tests"
```

---

### Task 3: Config loading (`Config.hs`)

**Files:**
- Create: `src/Hypell/Config.hs`

- [ ] **Step 1: Implement Config.hs**

```haskell
module Hypell.Config
  ( Config(..)
  , loadConfig
  , defaultEngineConfig
  ) where

import Data.ByteString (ByteString)
import Data.Text (Text)
import qualified Data.Text.Encoding as TE
import Data.Yaml (FromJSON(..), decodeFileThrow, withObject, (.:), (.:?), (.!=))
import GHC.Generics (Generic)
import System.Environment (lookupEnv)
import Hypell.Types

data Config = Config
  { cfgNetwork    :: Network
  , cfgApiUrl     :: Text
  , cfgWsUrl      :: Text
  , cfgPrivateKey :: ByteString
  , cfgRisk       :: RiskLimits
  , cfgEngine     :: EngineConfig
  , cfgLogLevel   :: LogLevel
  } deriving stock (Show)

defaultEngineConfig :: EngineConfig
defaultEngineConfig = EngineConfig
  { ecEventQueueSize      = 4096
  , ecOrderPollIntervalMs = 2000
  , ecHeartbeatIntervalMs = 1000
  }

-- Internal: YAML file structure (without private key)
data ConfigFile = ConfigFile
  { cfNetwork  :: Network
  , cfApiUrl   :: Text
  , cfWsUrl    :: Text
  , cfRisk     :: RiskLimits
  , cfEngine   :: EngineConfig
  , cfLogLevel :: LogLevel
  } deriving stock (Generic)

instance FromJSON ConfigFile where
  parseJSON = withObject "ConfigFile" $ \o -> ConfigFile
    <$> o .: "network"
    <*> o .: "apiUrl"
    <*> o .: "wsUrl"
    <*> o .: "risk"
    <*> o .:? "engine" .!= defaultEngineConfig
    <*> (o .:? "logging" >>= \case
           Nothing -> pure Info
           Just lo -> withObject "logging" (\l -> l .:? "level" .!= Info) lo)

loadConfig :: FilePath -> IO Config
loadConfig path = do
  cf <- decodeFileThrow path
  pk <- lookupEnv "HYPELL_PRIVATE_KEY" >>= \case
    Nothing -> error "HYPELL_PRIVATE_KEY environment variable not set"
    Just k  -> pure (TE.encodeUtf8 $ Data.Text.pack k)
  pure Config
    { cfgNetwork    = cfNetwork cf
    , cfgApiUrl     = cfApiUrl cf
    , cfgWsUrl      = cfWsUrl cf
    , cfgPrivateKey = pk
    , cfgRisk       = cfRisk cf
    , cfgEngine     = cfEngine cf
    , cfgLogLevel   = cfLogLevel cf
    }
```

The `loadConfig` reads the YAML file and overlays the private key from the environment. Requires `import qualified Data.Text` for `Data.Text.pack`.

- [ ] **Step 2: Verify it compiles**

Run: `cabal build lib:hypell`
Expected: Compiles successfully

- [ ] **Step 3: Commit**

```bash
git add src/Hypell/Config.hs
git commit -m "feat: YAML + env config loading"
```

---

## Chunk 2: Effect Definitions + Log

### Task 4: Log effect

**Files:**
- Create: `src/Hypell/Effect/Log.hs`

- [ ] **Step 1: Implement Log effect**

```haskell
module Hypell.Effect.Log
  ( Log
  , log
  , logDebug
  , logWarn
  , logError
  , runLog
  , mkLogAction
  ) where

import Prelude hiding (log)
import Colog.Core (LogAction(..))
import Data.Text (Text)
import qualified Data.Text.IO as TIO
import Data.Time (getCurrentTime)
import Effectful
import Effectful.Dispatch.Static
import Hypell.Types (LogLevel(..))

data Log :: Effect
type instance DispatchOf Log = Static WithSideEffects
newtype instance StaticRep Log = Log (LogAction IO Text)

log :: Log :> es => Text -> Eff es ()
log msg = do
  Log (LogAction action) <- getStaticRep
  unsafeEff_ $ action msg

logDebug :: Log :> es => Text -> Eff es ()
logDebug = log . ("[DEBUG] " <>)

logWarn :: Log :> es => Text -> Eff es ()
logWarn = log . ("[WARN] " <>)

logError :: Log :> es => Text -> Eff es ()
logError = log . ("[ERROR] " <>)

runLog :: IOE :> es => LogAction IO Text -> Eff (Log : es) a -> Eff es a
runLog action = evalStaticRep (Log action)

mkLogAction :: LogLevel -> LogAction IO Text
mkLogAction minLevel = LogAction $ \msg -> do
  let msgLevel = parseLevel msg
  when (msgLevel >= minLevel) $ do
    t <- getCurrentTime
    TIO.putStrLn $ "[" <> tshow t <> "] " <> msg
  where
    tshow = Data.Text.pack . show
    parseLevel m
      | "[DEBUG]" `Data.Text.isPrefixOf` m = Debug
      | "[WARN]"  `Data.Text.isPrefixOf` m = Warn
      | "[ERROR]" `Data.Text.isPrefixOf` m = Error
      | otherwise                          = Info
```

- [ ] **Step 2: Verify compiles**

Run: `cabal build lib:hypell`
Expected: Compiles

- [ ] **Step 3: Commit**

```bash
git add src/Hypell/Effect/Log.hs
git commit -m "feat: Log effect with co-log-core"
```

---

### Task 5: Dynamic effect definitions (Exchange, MarketData, Account, RiskControl, OrderManager, AlgoExec)

**Files:**
- Create: `src/Hypell/Effect/Exchange.hs`
- Create: `src/Hypell/Effect/MarketData.hs`
- Create: `src/Hypell/Effect/Account.hs`
- Create: `src/Hypell/Effect/RiskControl.hs`
- Create: `src/Hypell/Effect/OrderManager.hs`
- Create: `src/Hypell/Effect/AlgoExec.hs`

- [ ] **Step 1: Implement Exchange effect**

```haskell
module Hypell.Effect.Exchange
  ( Exchange(..)
  , placeOrder
  , cancelOrder
  , cancelAll
  , getOpenOrders
  ) where

import Effectful
import Effectful.TH (makeEffect)
import Hypell.Types

data Exchange :: Effect where
  PlaceOrder    :: OrderRequest -> Exchange m OrderResponse
  CancelOrder   :: CancelRequest -> Exchange m CancelResponse
  CancelAll     :: Exchange m ()
  GetOpenOrders :: Exchange m [Order]

makeEffect ''Exchange
```

- [ ] **Step 2: Implement MarketData effect**

```haskell
module Hypell.Effect.MarketData
  ( MarketData(..)
  , getSpotMeta
  , getSpotAssetCtxs
  , getOrderBook
  , subscribeTrades
  ) where

import Effectful
import Effectful.TH (makeEffect)
import Hypell.Types

data MarketData :: Effect where
  GetSpotMeta      :: MarketData m SpotMeta
  GetSpotAssetCtxs :: MarketData m [SpotAssetCtx]
  GetOrderBook     :: Coin -> MarketData m OrderBook
  SubscribeTrades  :: Coin -> MarketData m ()

makeEffect ''MarketData
```

- [ ] **Step 3: Implement Account effect**

```haskell
module Hypell.Effect.Account
  ( Account(..)
  , getBalances
  , getUserTrades
  ) where

import Effectful
import Effectful.TH (makeEffect)
import Hypell.Types

data Account :: Effect where
  GetBalances   :: Account m [TokenBalance]
  GetUserTrades :: Account m [UserTrade]

makeEffect ''Account
```

- [ ] **Step 4: Implement RiskControl effect**

```haskell
module Hypell.Effect.RiskControl
  ( RiskControl(..)
  , checkOrder
  , getRiskLimits
  , updateRiskLimits
  ) where

import Effectful
import Effectful.TH (makeEffect)
import Hypell.Types

data RiskControl :: Effect where
  CheckOrder       :: OrderRequest -> RiskControl m RiskResult
  GetRiskLimits    :: RiskControl m RiskLimits
  UpdateRiskLimits :: RiskLimits -> RiskControl m ()

makeEffect ''RiskControl
```

- [ ] **Step 5: Implement OrderManager effect**

```haskell
module Hypell.Effect.OrderManager
  ( OrderManager(..)
  , ManagedOrder(..)
  , submitOrder
  , trackOrder
  , cancelManaged
  ) where

import Effectful
import Effectful.TH (makeEffect)
import Data.Time (UTCTime)
import Hypell.Types

data ManagedOrder = ManagedOrder
  { moId        :: OrderId
  , moRequest   :: OrderRequest
  , moStatus    :: OrderStatus
  , moCreatedAt :: UTCTime
  } deriving stock (Eq, Show)

data OrderManager :: Effect where
  SubmitOrder   :: OrderRequest -> OrderManager m ManagedOrder
  TrackOrder    :: OrderId -> OrderManager m OrderStatus
  CancelManaged :: OrderId -> OrderManager m ()

makeEffect ''OrderManager
```

- [ ] **Step 6: Implement AlgoExec effect**

```haskell
module Hypell.Effect.AlgoExec
  ( AlgoExec(..)
  , AlgoHandle(..)
  , runTWAP
  , runIceberg
  , cancelAlgo
  ) where

import Control.Concurrent.Async (Async)
import Control.Concurrent.STM (TVar)
import Data.Text (Text)
import Effectful
import Effectful.TH (makeEffect)
import Hypell.Types

data AlgoHandle = AlgoHandle
  { ahId     :: Text
  , ahThread :: Async ()
  , ahParams :: AlgoParams
  , ahStatus :: TVar AlgoStatus
  }

data AlgoExec :: Effect where
  RunTWAP    :: TWAPParams -> AlgoExec m AlgoHandle
  RunIceberg :: IcebergParams -> AlgoExec m AlgoHandle
  CancelAlgo :: AlgoHandle -> AlgoExec m ()

makeEffect ''AlgoExec
```

- [ ] **Step 7: Verify all effects compile**

Run: `cabal build lib:hypell`
Expected: Compiles (some modules will have stub warnings)

- [ ] **Step 8: Commit**

```bash
git add src/Hypell/Effect/
git commit -m "feat: all effect definitions with TH-generated helpers"
```

---

### Task 6: Strategy typeclass

**Files:**
- Create: `src/Hypell/Strategy.hs`

- [ ] **Step 1: Implement Strategy.hs**

```haskell
module Hypell.Strategy
  ( Strategy(..)
  ) where

import Data.Text (Text)
import Effectful
import Hypell.Types
import Hypell.Effect.Log (Log)
import Hypell.Effect.MarketData (MarketData)
import Hypell.Effect.Account (Account)
import Hypell.Effect.OrderManager (OrderManager)

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

- [ ] **Step 2: Verify compiles**

Run: `cabal build lib:hypell`
Expected: Compiles

- [ ] **Step 3: Commit**

```bash
git add src/Hypell/Strategy.hs
git commit -m "feat: Strategy typeclass"
```

---

## Chunk 3: Risk + Pure Interpreters + Tests

### Task 7: Risk pure function + tests

**Files:**
- Create: `src/Hypell/Risk.hs`
- Create: `test/Test/Hypell/RiskTest.hs`

- [ ] **Step 1: Write failing risk tests**

```haskell
module Test.Hypell.RiskTest (tests) where

import Test.Tasty
import Test.Tasty.HUnit
import Test.Tasty.QuickCheck
import Data.Map.Strict qualified as Map
import Data.Scientific (scientific)
import Data.Time.Calendar (fromGregorian)
import Data.Time.Clock (UTCTime(..), secondsToNominalDiffTime)
import Hypell.Types
import Hypell.Risk

defaultLimits :: RiskLimits
defaultLimits = RiskLimits
  { rlMaxOrderSize    = scientific 1000 0
  , rlMaxPositionSize = Map.singleton (SpotCoin "HYPE/USDC") (scientific 5000 0)
  , rlMaxDailyVolume  = scientific 50000 0
  , rlCooldownMs      = 500
  }

emptyStats :: DailyStats
emptyStats = DailyStats
  { dsTotalVolume   = 0
  , dsTotalTrades   = 0
  , dsLastOrderTime = Nothing
  , dsDate          = fromGregorian 2026 3 16
  }

now :: UTCTime
now = UTCTime (fromGregorian 2026 3 16) (secondsToNominalDiffTime 43200)

mkOrder :: Coin -> Side -> Scientific -> OrderRequest
mkOrder coin side sz = OrderRequest
  { orCoin = coin, orSide = side, orSize = sz
  , orType = Market, orCloid = Nothing
  }

tests :: TestTree
tests = testGroup "Risk"
  [ testCase "passes valid order" $
      evaluateRisk defaultLimits emptyStats mempty now (mkOrder (SpotCoin "HYPE/USDC") Buy 100)
        @?= RiskPass

  , testCase "rejects order exceeding max size" $
      case evaluateRisk defaultLimits emptyStats mempty now (mkOrder (SpotCoin "HYPE/USDC") Buy 1500) of
        RiskReject _ -> pure ()
        RiskPass     -> assertFailure "expected rejection"

  , testCase "rejects order exceeding position limit" $ do
      let positions = Map.singleton (SpotCoin "HYPE/USDC")
            (TokenBalance (SpotCoin "HYPE/USDC") 4500 0 4500)
      case evaluateRisk defaultLimits emptyStats positions now (mkOrder (SpotCoin "HYPE/USDC") Buy 600) of
        RiskReject _ -> pure ()
        RiskPass     -> assertFailure "expected rejection"

  , testCase "rejects order exceeding daily volume" $ do
      let stats = emptyStats { dsTotalVolume = scientific 49500 0 }
      case evaluateRisk defaultLimits stats mempty now (mkOrder (SpotCoin "HYPE/USDC") Buy 600) of
        RiskReject _ -> pure ()
        RiskPass     -> assertFailure "expected rejection"

  , testCase "rejects order within cooldown period" $ do
      let recentTime = UTCTime (fromGregorian 2026 3 16) (secondsToNominalDiffTime 43199.9)
          stats = emptyStats { dsLastOrderTime = Just recentTime }
      case evaluateRisk defaultLimits stats mempty now (mkOrder (SpotCoin "HYPE/USDC") Buy 100) of
        RiskReject _ -> pure ()
        RiskPass     -> assertFailure "expected cooldown rejection"

  , testCase "passes order after cooldown period" $ do
      let oldTime = UTCTime (fromGregorian 2026 3 16) (secondsToNominalDiffTime 43199)
          stats = emptyStats { dsLastOrderTime = Just oldTime }
      evaluateRisk defaultLimits stats mempty now (mkOrder (SpotCoin "HYPE/USDC") Buy 100)
        @?= RiskPass

  , testProperty "any order above maxOrderSize is rejected" $ \(Positive sz) ->
      let bigSz = scientific (1000 + sz) 0
          result = evaluateRisk defaultLimits emptyStats mempty now
                     (mkOrder (SpotCoin "X") Buy bigSz)
      in result /= RiskPass
  ]
```

- [ ] **Step 2: Wire into Spec.hs**

```haskell
import Test.Tasty
import qualified Test.Hypell.TypesTest
import qualified Test.Hypell.RiskTest

main :: IO ()
main = defaultMain $ testGroup "Hypell"
  [ Test.Hypell.TypesTest.tests
  , Test.Hypell.RiskTest.tests
  ]
```

- [ ] **Step 3: Run tests to verify they fail**

Run: `cabal test`
Expected: FAIL — `Hypell.Risk` not found

- [ ] **Step 4: Implement Risk.hs**

```haskell
module Hypell.Risk
  ( evaluateRisk
  ) where

import Data.Map.Strict qualified as Map
import Data.Scientific (Scientific)
import Data.Time (UTCTime, diffUTCTime)
import Hypell.Types

evaluateRisk
  :: RiskLimits
  -> DailyStats
  -> Map.Map Coin TokenBalance
  -> UTCTime           -- current time, for cooldown check
  -> OrderRequest
  -> RiskResult
evaluateRisk limits stats positions now req
  | orSize req > rlMaxOrderSize limits
    = RiskReject $ "Order size " <> tshow (orSize req)
        <> " exceeds max " <> tshow (rlMaxOrderSize limits)
  | exceedsPositionLimit
    = RiskReject $ "Would exceed position limit for " <> tshow (orCoin req)
  | dsTotalVolume stats + orderNotional > rlMaxDailyVolume limits
    = RiskReject "Daily volume limit exceeded"
  | violatesCooldown
    = RiskReject "Order cooldown period not elapsed"
  | otherwise
    = RiskPass
  where
    exceedsPositionLimit = case Map.lookup (orCoin req) (rlMaxPositionSize limits) of
      Nothing    -> False
      Just maxSz -> currentPos + orSize req > maxSz
    currentPos = maybe 0 tbTotal $ Map.lookup (orCoin req) positions
    orderNotional = orSize req  -- for spot, notional ≈ size (simplified)
    violatesCooldown = case dsLastOrderTime stats of
      Nothing -> False
      Just lastTime ->
        let elapsedMs = round (diffUTCTime now lastTime * 1000) :: Int
        in elapsedMs < rlCooldownMs limits

tshow :: Show a => a -> Text
tshow = Data.Text.pack . show
```

- [ ] **Step 5: Run tests**

Run: `cabal test`
Expected: All risk tests PASS

- [ ] **Step 6: Commit**

```bash
git add src/Hypell/Risk.hs test/Test/Hypell/RiskTest.hs test/Spec.hs
git commit -m "feat: evaluateRisk pure function with unit + property tests"
```

---

### Task 8: Pure interpreters (Exchange, MarketData, Account, RiskControl)

**Files:**
- Create: `src/Hypell/Interpreter/Exchange/Pure.hs`
- Create: `src/Hypell/Interpreter/MarketData/Pure.hs`
- Create: `src/Hypell/Interpreter/Account/Pure.hs`
- Create: `src/Hypell/Interpreter/RiskControl.hs`

- [ ] **Step 1: Implement Exchange Pure interpreter**

```haskell
module Hypell.Interpreter.Exchange.Pure
  ( MockExchangeState(..)
  , emptyMockExchange
  , runExchangePure
  ) where

import Data.Map.Strict qualified as Map
import Effectful
import Effectful.Dispatch.Dynamic
import Effectful.State.Static.Local
import Hypell.Types
import Hypell.Effect.Exchange

data MockExchangeState = MockExchangeState
  { mesOrders    :: Map.Map OrderId OrderRequest
  , mesNextId    :: OrderId
  , mesFillQueue :: [OrderResponse]
  } deriving stock (Eq, Show)

emptyMockExchange :: MockExchangeState
emptyMockExchange = MockExchangeState Map.empty 1 []

runExchangePure
  :: State MockExchangeState :> es
  => Eff (Exchange : es) a -> Eff es a
runExchangePure = interpret_ $ \case
  PlaceOrder req -> do
    st <- get
    let oid = mesNextId st
    put st { mesOrders = Map.insert oid req (mesOrders st)
           , mesNextId = oid + 1 }
    case mesFillQueue st of
      (r:rs) -> do
        modify $ \s -> s { mesFillQueue = rs }
        pure r
      [] -> pure (OrderResting oid)
  CancelOrder (CancelById _ oid) -> do
    modify $ \s -> s { mesOrders = Map.delete oid (mesOrders s) }
    pure CancelSuccess
  CancelOrder (CancelByCloid _ _) -> pure CancelSuccess
  CancelAll -> modify $ \s -> s { mesOrders = Map.empty }
  GetOpenOrders -> pure []  -- simplified
```

- [ ] **Step 2: Implement MarketData Pure interpreter**

```haskell
module Hypell.Interpreter.MarketData.Pure
  ( MockMarketDataState(..)
  , emptyMockMarketData
  , runMarketDataPure
  ) where

import Effectful
import Effectful.Dispatch.Dynamic
import Effectful.State.Static.Local
import Hypell.Types
import Hypell.Effect.MarketData

data MockMarketDataState = MockMarketDataState
  { mmdSpotMeta      :: SpotMeta
  , mmdAssetCtxs     :: [SpotAssetCtx]
  , mmdOrderBooks    :: [(Coin, OrderBook)]
  } deriving stock (Eq, Show)

emptyMockMarketData :: MockMarketDataState
emptyMockMarketData = MockMarketDataState
  (SpotMeta [] []) [] []

runMarketDataPure
  :: State MockMarketDataState :> es
  => Eff (MarketData : es) a -> Eff es a
runMarketDataPure = interpret_ $ \case
  GetSpotMeta      -> gets mmdSpotMeta
  GetSpotAssetCtxs -> gets mmdAssetCtxs
  GetOrderBook c   -> do
    obs <- gets mmdOrderBooks
    case lookup c obs of
      Just ob -> pure ob
      Nothing -> pure $ OrderBook [] [] (read "2026-01-01 00:00:00 UTC")
  SubscribeTrades _ -> pure ()
```

- [ ] **Step 3: Implement Account Pure interpreter**

```haskell
module Hypell.Interpreter.Account.Pure
  ( runAccountPure
  ) where

import Effectful
import Effectful.Dispatch.Dynamic
import Effectful.State.Static.Local
import Hypell.Types
import Hypell.Effect.Account

runAccountPure
  :: State [TokenBalance] :> es
  => Eff (Account : es) a -> Eff es a
runAccountPure = interpret_ $ \case
  GetBalances   -> get
  GetUserTrades -> pure []
```

- [ ] **Step 4: Implement RiskControl interpreter (shared for IO/Pure)**

```haskell
module Hypell.Interpreter.RiskControl
  ( runRiskControlPure
  ) where

import Data.Map.Strict qualified as Map
import Data.Time.Clock (UTCTime)
import Effectful
import Effectful.Dispatch.Dynamic
import Effectful.State.Static.Local
import Hypell.Types
import Hypell.Effect.RiskControl
import Hypell.Risk (evaluateRisk)

runRiskControlPure
  :: (State RiskLimits :> es, State DailyStats :> es, State (Map.Map Coin TokenBalance) :> es, State UTCTime :> es)
  => Eff (RiskControl : es) a -> Eff es a
runRiskControlPure = interpret_ $ \case
  CheckOrder req -> do
    limits <- get
    stats  <- get
    positions <- get
    now <- get @UTCTime
    pure $ evaluateRisk limits stats positions now req
  GetRiskLimits -> get
  UpdateRiskLimits newLimits -> put newLimits
```

- [ ] **Step 5: Verify compiles**

Run: `cabal build lib:hypell`
Expected: Compiles

- [ ] **Step 6: Commit**

```bash
git add src/Hypell/Interpreter/
git commit -m "feat: pure interpreters for Exchange, MarketData, Account, RiskControl"
```

---

### Task 9: OrderManager + AlgoExec interpreters (Pure + IO stubs)

**Files:**
- Create: `src/Hypell/Interpreter/OrderManager.hs`
- Create: `src/Hypell/Interpreter/AlgoExec.hs`

Note: `EngineEnv` in this plan uses `eeRestClient :: RestClient` and `eeWsClient :: WsClient` rather than the spec's `eeHttpMgr`/`eeWsConn`. This is a deliberate refinement — `RestClient` and `WsClient` encapsulate the low-level connection details, keeping `EngineEnv` higher-level.

- [ ] **Step 1: Implement OrderManager pure interpreter**

```haskell
module Hypell.Interpreter.OrderManager
  ( runOrderManagerPure
  ) where

import Data.Map.Strict qualified as Map
import Data.Time (UTCTime)
import Data.Time.Clock (getCurrentTime)
import Effectful
import Effectful.Dispatch.Dynamic
import Effectful.State.Static.Local
import Hypell.Types
import Hypell.Effect.Exchange (Exchange, placeOrder)
import Hypell.Effect.OrderManager

runOrderManagerPure
  :: (Exchange :> es, State (Map.Map OrderId ManagedOrder) :> es)
  => Eff (OrderManager : es) a -> Eff es a
runOrderManagerPure = interpret_ $ \case
  SubmitOrder req -> do
    resp <- placeOrder req
    let (oid, status) = case resp of
          OrderResting i   -> (i, OsResting)
          OrderFilled s p  -> (0, OsFilled s p)
          OrderError t     -> (0, OsRejected t)
    let mo = ManagedOrder oid req status (read "2026-01-01 00:00:00 UTC")
    modify $ Map.insert oid mo
    pure mo
  TrackOrder oid -> do
    orders <- get @(Map.Map OrderId ManagedOrder)
    pure $ maybe OsCancelled moStatus (Map.lookup oid orders)
  CancelManaged oid ->
    modify $ Map.delete @OrderId @ManagedOrder oid
```

- [ ] **Step 2: Implement AlgoExec pure interpreter**

```haskell
module Hypell.Interpreter.AlgoExec
  ( runAlgoExecPure
  ) where

import Control.Concurrent.Async (async)
import Control.Concurrent.STM (newTVarIO)
import Effectful
import Effectful.Dispatch.Dynamic
import Hypell.Types
import Hypell.Effect.AlgoExec

runAlgoExecPure
  :: IOE :> es
  => Eff (AlgoExec : es) a -> Eff es a
runAlgoExecPure = interpret_ $ \case
  RunTWAP params -> liftIO $ do
    statusVar <- newTVarIO (AlgoRunning 0)
    thread <- async (pure ())
    pure AlgoHandle
      { ahId     = "mock-twap"
      , ahThread = thread
      , ahParams = AlgoTWAP params
      , ahStatus = statusVar
      }
  RunIceberg params -> liftIO $ do
    statusVar <- newTVarIO (AlgoRunning 0)
    thread <- async (pure ())
    pure AlgoHandle
      { ahId     = "mock-iceberg"
      , ahThread = thread
      , ahParams = AlgoIceberg params
      , ahStatus = statusVar
      }
  CancelAlgo _ -> pure ()
```

- [ ] **Step 3: Verify compiles**

Run: `cabal build lib:hypell`
Expected: Compiles

- [ ] **Step 4: Commit**

```bash
git add src/Hypell/Interpreter/OrderManager.hs src/Hypell/Interpreter/AlgoExec.hs
git commit -m "feat: pure interpreters for OrderManager and AlgoExec"
```

---

### Task 10: Strategy integration test

**Files:**
- Create: `test/Test/Hypell/StrategyTest.hs`

- [ ] **Step 1: Write strategy integration test**

```haskell
module Test.Hypell.StrategyTest (tests) where

import Test.Tasty
import Test.Tasty.HUnit
import Data.Map.Strict qualified as Map
import Data.Scientific (scientific)
import Data.Time.Calendar (fromGregorian)
import Effectful
import Effectful.State.Static.Local
import Hypell.Types
import Hypell.Strategy
import Hypell.Effect.MarketData
import Hypell.Effect.Account
import Hypell.Effect.Log
import Hypell.Interpreter.MarketData.Pure
import Hypell.Interpreter.Account.Pure
import Colog.Core (LogAction(..))

-- A trivial test strategy: buy on every trade event
data BuyOnTrade = BuyOnTrade
  deriving stock (Eq, Show)

instance Strategy BuyOnTrade where
  strategyName _ = "buy-on-trade"
  initStrategy s = pure s
  onEvent s (EventTrade trade) = pure
    ( s
    , [ ActionPlace OrderRequest
          { orCoin  = trCoin trade
          , orSide  = Buy
          , orSize  = scientific 10 0
          , orType  = Market
          , orCloid = Nothing
          }
      ]
    )
  onEvent s _ = pure (s, [])
  onShutdown _ = pure ()

tests :: TestTree
tests = testGroup "Strategy"
  [ testCase "BuyOnTrade emits ActionPlace on trade event" $ do
      let trade = Trade
            { trCoin  = SpotCoin "HYPE/USDC"
            , trSide  = Buy
            , trPrice = scientific 25 0
            , trSize  = scientific 100 0
            , trTime  = read "2026-03-16 12:00:00 UTC"
            }
      (_, actions) <- runEff
        . runLog (LogAction $ \_ -> pure ())
        . evalState ([] :: [TokenBalance])
        . runAccountPure
        . evalState emptyMockMarketData
        . runMarketDataPure
        $ onEvent BuyOnTrade (EventTrade trade)
      length actions @?= 1
      case head actions of
        ActionPlace req -> do
          orCoin req @?= SpotCoin "HYPE/USDC"
          orSide req @?= Buy
          orSize req @?= scientific 10 0
        _ -> assertFailure "expected ActionPlace"
  ]
```

- [ ] **Step 2: Wire into Spec.hs**

```haskell
import Test.Tasty
import qualified Test.Hypell.TypesTest
import qualified Test.Hypell.RiskTest
import qualified Test.Hypell.StrategyTest

main :: IO ()
main = defaultMain $ testGroup "Hypell"
  [ Test.Hypell.TypesTest.tests
  , Test.Hypell.RiskTest.tests
  , Test.Hypell.StrategyTest.tests
  ]
```

- [ ] **Step 3: Run tests**

Run: `cabal test`
Expected: All tests PASS

- [ ] **Step 4: Commit**

```bash
git add test/Test/Hypell/StrategyTest.hs test/Spec.hs
git commit -m "feat: strategy integration test with pure interpreters"
```

---

## Chunk 4: API Layer (REST, Signing, WebSocket)

### Task 11: EIP-712 signing (`Api.Signing`)

**Files:**
- Create: `src/Hypell/Api/Signing.hs`

- [ ] **Step 1: Implement signing module**

This module handles EIP-712 signing for Hyperliquid. Key operations:
- `signRequest`: sign a JSON action payload with the private key
- `makeNonce`: generate millisecond timestamp nonce
- Uses `crypton` for secp256k1 ECDSA and keccak256

```haskell
module Hypell.Api.Signing
  ( SignedRequest(..)
  , signRequest
  , makeNonce
  ) where

import Crypto.Hash (hashWith, Keccak_256(..))
import Crypto.PubKey.ECC.ECDSA (signWith, PrivateKey(..))
import Crypto.PubKey.ECC.Types (getCurveByName, CurveName(SEC_p256k1))
import Data.Aeson (Value, object, (.=), encode)
import Data.ByteArray (convert)
import Data.ByteString (ByteString)
import qualified Data.ByteString.Lazy as BL
import Data.Text (Text)
import Data.Time.Clock.POSIX (getPOSIXTime)
import Data.Word (Word64)

data SignedRequest = SignedRequest
  { srAction    :: Value
  , srNonce     :: Word64
  , srSignature :: Value
  } deriving stock (Show)

makeNonce :: IO Word64
makeNonce = do
  t <- getPOSIXTime
  pure $ round (t * 1000)

-- Placeholder: actual EIP-712 signing requires structured type hashing.
-- This will be refined when testing against Hyperliquid testnet.
signRequest :: ByteString -> Value -> Word64 -> IO SignedRequest
signRequest _privateKey action nonce = do
  -- TODO: Implement EIP-712 typed data hashing and secp256k1 signing
  -- For now, return a stub signature for compilation
  let sig = object ["r" .= ("" :: Text), "s" .= ("" :: Text), "v" .= (27 :: Int)]
  pure SignedRequest
    { srAction    = action
    , srNonce     = nonce
    , srSignature = sig
    }
```

Note: Full EIP-712 implementation deferred to testnet integration (Task 15). The structure is correct but the hash computation is stubbed.

- [ ] **Step 2: Verify compiles**

Run: `cabal build lib:hypell`
Expected: Compiles

- [ ] **Step 3: Commit**

```bash
git add src/Hypell/Api/Signing.hs
git commit -m "feat: signing module scaffold (EIP-712 stub)"
```

---

### Task 12: REST client (`Api.Rest`)

**Files:**
- Create: `src/Hypell/Api/Rest.hs`

- [ ] **Step 1: Implement REST client**

```haskell
module Hypell.Api.Rest
  ( RestClient(..)
  , newRestClient
  , postInfo
  , postExchange
  ) where

import Data.Aeson (Value, encode, eitherDecode, object, (.=), ToJSON)
import Data.ByteString.Lazy (ByteString)
import Data.Text (Text)
import Network.HTTP.Client
import Network.HTTP.Client.TLS (tlsManagerSettings)
import Network.HTTP.Types.Status (statusCode)
import Hypell.Api.Signing (SignedRequest(..), signRequest, makeNonce)

data RestClient = RestClient
  { rcManager :: Manager
  , rcBaseUrl :: String
  , rcPrivKey :: Data.ByteString.ByteString
  }

newRestClient :: Text -> Data.ByteString.ByteString -> IO RestClient
newRestClient baseUrl privKey = do
  mgr <- newManager tlsManagerSettings
  pure RestClient
    { rcManager = mgr
    , rcBaseUrl = Data.Text.unpack baseUrl
    , rcPrivKey = privKey
    }

-- POST /info: unsigned query
postInfo :: RestClient -> Value -> IO (Either String Value)
postInfo rc payload = do
  req <- parseRequest (rcBaseUrl rc <> "/info")
  let req' = req
        { method = "POST"
        , requestBody = RequestBodyLBS (encode payload)
        , requestHeaders = [("Content-Type", "application/json")]
        }
  resp <- httpLbs req' (rcManager rc)
  pure $ eitherDecode (responseBody resp)

-- POST /exchange: signed action
postExchange :: RestClient -> Value -> IO (Either String Value)
postExchange rc action = do
  nonce <- makeNonce
  signed <- signRequest (rcPrivKey rc) action nonce
  let payload = object
        [ "action"    .= srAction signed
        , "nonce"     .= srNonce signed
        , "signature" .= srSignature signed
        ]
  req <- parseRequest (rcBaseUrl rc <> "/exchange")
  let req' = req
        { method = "POST"
        , requestBody = RequestBodyLBS (encode payload)
        , requestHeaders = [("Content-Type", "application/json")]
        }
  resp <- httpLbs req' (rcManager rc)
  pure $ eitherDecode (responseBody resp)
```

- [ ] **Step 2: Verify compiles**

Run: `cabal build lib:hypell`
Expected: Compiles

- [ ] **Step 3: Commit**

```bash
git add src/Hypell/Api/Rest.hs
git commit -m "feat: REST client for /info and /exchange endpoints"
```

---

### Task 13: WebSocket client (`Api.WebSocket`)

**Files:**
- Create: `src/Hypell/Api/WebSocket.hs`

- [ ] **Step 1: Implement WebSocket client**

```haskell
module Hypell.Api.WebSocket
  ( WsClient(..)
  , connectWs
  , subscribe
  , wsListenerLoop
  ) where

import Control.Concurrent (threadDelay)
import Control.Concurrent.STM
import Control.Exception (SomeException, try)
import Data.Aeson (Value, object, (.=), encode, eitherDecode)
import qualified Data.Aeson.KeyMap as KM
import Data.Aeson.Key (fromText)
import Data.Text (Text)
import qualified Data.Text as T
import qualified Network.WebSockets as WS
import Wuss (runSecureClient)
import Hypell.Types

data WsClient = WsClient
  { wsConn     :: TVar (Maybe WS.Connection)
  , wsEventBus :: TBQueue MarketEvent
  , wsHost     :: String
  , wsPath     :: String
  }

connectWs :: Text -> TBQueue MarketEvent -> IO WsClient
connectWs wsUrl eventBus = do
  connVar <- newTVarIO Nothing
  let (host, path) = parseWsUrl wsUrl
  pure WsClient
    { wsConn     = connVar
    , wsEventBus = eventBus
    , wsHost     = host
    , wsPath     = path
    }
  where
    parseWsUrl url =
      let stripped = T.drop 6 url  -- drop "wss://"
          (h, p) = T.break (== '/') stripped
      in (T.unpack h, T.unpack $ if T.null p then "/" else p)

subscribe :: WS.Connection -> Coin -> IO ()
subscribe conn (SpotCoin coin) =
  WS.sendTextData conn $ encode $ object
    [ "method" .= ("subscribe" :: Text)
    , "subscription" .= object
        [ "type" .= ("trades" :: Text)
        , "coin" .= coin
        ]
    ]

-- Main WS loop with exponential backoff reconnect
wsListenerLoop :: WsClient -> IO ()
wsListenerLoop client = go 1
  where
    maxRetries = 20 :: Int
    maxDelay   = 30_000_000 :: Int  -- 30 seconds

    go retryCount
      | retryCount > maxRetries = pure ()  -- give up
      | otherwise = do
          result <- try $ runSecureClient (wsHost client) 443 (wsPath client) $ \conn -> do
            atomically $ writeTVar (wsConn client) (Just conn)
            listenLoop conn
          case result of
            Left (_ :: SomeException) -> do
              atomically $ writeTVar (wsConn client) Nothing
              let delay = min maxDelay (1_000_000 * 2 ^ (retryCount - 1))
              threadDelay delay
              go (retryCount + 1)
            Right _ -> go 1  -- clean disconnect, reset retry

    listenLoop conn = do
      msg <- WS.receiveData conn
      case eitherDecode msg of
        Left _  -> listenLoop conn  -- skip unparseable
        Right v -> do
          -- TODO: parse Hyperliquid WS message format into MarketEvent
          listenLoop conn
```

- [ ] **Step 2: Verify compiles**

Run: `cabal build lib:hypell`
Expected: Compiles

- [ ] **Step 3: Commit**

```bash
git add src/Hypell/Api/WebSocket.hs
git commit -m "feat: WebSocket client with exponential backoff reconnect"
```

---

## Chunk 5: IO Interpreters + Engine

### Task 14: IO interpreters (Exchange, MarketData, Account)

**Files:**
- Create: `src/Hypell/Interpreter/Exchange/IO.hs`
- Create: `src/Hypell/Interpreter/MarketData/IO.hs`
- Create: `src/Hypell/Interpreter/Account/IO.hs`

- [ ] **Step 1: Implement Exchange IO interpreter**

```haskell
module Hypell.Interpreter.Exchange.IO
  ( runExchangeIO
  ) where

import Control.Concurrent.STM
import Data.Aeson (object, (.=), Value)
import qualified Data.Map.Strict as Map
import Effectful
import Effectful.Dispatch.Dynamic
import Hypell.Types
import Hypell.Effect.Exchange
import Hypell.Effect.Log (Log, log, logError)
import Hypell.Api.Rest (RestClient, postExchange)

runExchangeIO
  :: (IOE :> es, Log :> es)
  => RestClient -> TVar (Map.Map OrderId Order) -> Eff (Exchange : es) a -> Eff es a
runExchangeIO client ordersVar = interpret_ $ \case
  PlaceOrder req -> do
    let payload = encodeOrderAction req
    result <- liftIO $ postExchange client payload
    case result of
      Left err -> do
        logError $ "PlaceOrder failed: " <> Data.Text.pack err
        pure (OrderError $ Data.Text.pack err)
      Right val -> pure $ parseOrderResponse val

  CancelOrder req -> do
    let payload = encodeCancelAction req
    result <- liftIO $ postExchange client payload
    case result of
      Left err -> do
        logError $ "CancelOrder failed: " <> Data.Text.pack err
        pure (CancelError $ Data.Text.pack err)
      Right _ -> pure CancelSuccess

  CancelAll -> do
    orders <- liftIO $ atomically $ readTVar ordersVar
    -- Cancel each order individually
    mapM_ (\oid -> do
      let payload = encodeCancelAction (CancelById (SpotCoin "") oid)
      _ <- liftIO $ postExchange client payload
      pure ()
      ) (Map.keys orders)

  GetOpenOrders ->
    liftIO $ Map.elems <$> atomically (readTVar ordersVar)

-- Encoding helpers (Hyperliquid-specific JSON format)
encodeOrderAction :: OrderRequest -> Value
encodeOrderAction req = object
  [ "type" .= ("order" :: Text)
  , "orders" .= [ object
      [ "a"    .= coinToAssetIndex (orCoin req)
      , "b"    .= (orSide req == Buy)
      , "p"    .= priceStr req
      , "s"    .= show (orSize req)
      , "r"    .= False  -- not reduce-only
      , "t"    .= encodeTif req
      ] ]
  , "grouping" .= ("na" :: Text)
  ]

encodeCancelAction :: CancelRequest -> Value
encodeCancelAction (CancelById coin oid) = object
  [ "type" .= ("cancel" :: Text)
  , "cancels" .= [ object
      [ "a" .= coinToAssetIndex coin
      , "o" .= oid
      ] ]
  ]
encodeCancelAction (CancelByCloid coin cloid) = object
  [ "type" .= ("cancelByCloid" :: Text)
  , "cancels" .= [ object
      [ "asset" .= coinToAssetIndex coin
      , "cloid" .= cloid
      ] ]
  ]

coinToAssetIndex :: Coin -> Int
coinToAssetIndex (SpotCoin _) = 10000  -- simplified; real impl needs spot meta lookup

priceStr :: OrderRequest -> Text
priceStr req = case orType req of
  Limit p _ -> Data.Text.pack $ show p
  Market    -> "0"  -- market orders use slippage, not explicit price

encodeTif :: OrderRequest -> Value
encodeTif req = case orType req of
  Limit _ GTC -> object ["limit" .= object ["tif" .= ("Gtc" :: Text)]]
  Limit _ IOC -> object ["limit" .= object ["tif" .= ("Ioc" :: Text)]]
  Limit _ ALO -> object ["limit" .= object ["tif" .= ("Alo" :: Text)]]
  Market      -> object ["market" .= object []]

parseOrderResponse :: Value -> OrderResponse
parseOrderResponse _ = OrderError "TODO: parse Hyperliquid response"
-- TODO: implement proper parsing based on Hyperliquid response format
```

- [ ] **Step 2: Implement MarketData IO interpreter**

```haskell
module Hypell.Interpreter.MarketData.IO
  ( runMarketDataIO
  ) where

import Control.Concurrent.STM
import Data.Aeson (object, (.=))
import Effectful
import Effectful.Dispatch.Dynamic
import Hypell.Types
import Hypell.Effect.MarketData
import Hypell.Effect.Log (Log, log, logError)
import Hypell.Api.Rest (RestClient, postInfo)
import Hypell.Api.WebSocket (WsClient, subscribe)
import qualified Network.WebSockets as WS

runMarketDataIO
  :: (IOE :> es, Log :> es)
  => RestClient -> WsClient -> Eff (MarketData : es) a -> Eff es a
runMarketDataIO rest ws = interpret_ $ \case
  GetSpotMeta -> do
    result <- liftIO $ postInfo rest $ object ["type" .= ("spotMeta" :: Text)]
    case result of
      Left err  -> error $ "Failed to get spot meta: " <> err
      Right val -> case fromJSON val of
        Success sm -> pure sm
        Error e    -> error $ "Failed to parse spot meta: " <> e

  GetSpotAssetCtxs -> do
    result <- liftIO $ postInfo rest $ object ["type" .= ("spotMetaAndAssetCtxs" :: Text)]
    case result of
      Left err  -> error $ "Failed to get asset contexts: " <> err
      Right val -> case fromJSON val of
        Success ctxs -> pure ctxs
        Error e      -> error $ "Failed to parse asset contexts: " <> e

  GetOrderBook coin -> do
    result <- liftIO $ postInfo rest $ object
      [ "type" .= ("l2Book" :: Text)
      , "coin" .= coinToText coin
      ]
    case result of
      Left err  -> error $ "Failed to get order book: " <> err
      Right val -> case fromJSON val of
        Success ob -> pure ob
        Error e    -> error $ "Failed to parse order book: " <> e

  SubscribeTrades coin -> do
    mConn <- liftIO $ atomically $ readTVar (wsConn ws)
    case mConn of
      Nothing   -> logError "WebSocket not connected, cannot subscribe"
      Just conn -> liftIO $ subscribe conn coin

coinToText :: Coin -> Text
coinToText (SpotCoin t) = t
```

- [ ] **Step 3: Implement Account IO interpreter**

```haskell
module Hypell.Interpreter.Account.IO
  ( runAccountIO
  ) where

import Data.Aeson (object, (.=), fromJSON, Result(..))
import Data.Text (Text)
import Effectful
import Effectful.Dispatch.Dynamic
import Hypell.Types
import Hypell.Effect.Account
import Hypell.Effect.Log (Log, logError)
import Hypell.Api.Rest (RestClient, postInfo)

runAccountIO
  :: (IOE :> es, Log :> es)
  => RestClient -> Text -> Eff (Account : es) a -> Eff es a
runAccountIO rest walletAddr = interpret_ $ \case
  GetBalances -> do
    result <- liftIO $ postInfo rest $ object
      [ "type" .= ("spotClearinghouseState" :: Text)
      , "user" .= walletAddr
      ]
    case result of
      Left err  -> do
        logError $ "Failed to get balances: " <> Data.Text.pack err
        pure []
      Right val -> case fromJSON val of
        Success bals -> pure bals
        Error _      -> pure []

  GetUserTrades -> pure []  -- TODO: implement user fills query
```

- [ ] **Step 4: Verify compiles**

Run: `cabal build lib:hypell`
Expected: Compiles (with some TODO warnings)

- [ ] **Step 5: Commit**

```bash
git add src/Hypell/Interpreter/Exchange/IO.hs src/Hypell/Interpreter/MarketData/IO.hs src/Hypell/Interpreter/Account/IO.hs
git commit -m "feat: IO interpreters for Exchange, MarketData, Account"
```

---

### Task 14b: IO interpreters (RiskControl, OrderManager, AlgoExec)

**Files:**
- Create: `src/Hypell/Interpreter/RiskControl/IO.hs` (or extend existing `RiskControl.hs`)
- Create: `src/Hypell/Interpreter/OrderManager/IO.hs` (or extend existing `OrderManager.hs`)
- Create: `src/Hypell/Interpreter/AlgoExec/IO.hs` (or extend existing `AlgoExec.hs`)

- [ ] **Step 1: Implement RiskControl IO interpreter**

Add to `src/Hypell/Interpreter/RiskControl.hs`:

```haskell
-- Add to existing module:
import Control.Concurrent.STM
import Data.Time.Clock (getCurrentTime)

runRiskControlIO
  :: (IOE :> es)
  => TVar RiskLimits -> TVar DailyStats -> TVar (Map.Map Coin TokenBalance)
  -> Eff (RiskControl : es) a -> Eff es a
runRiskControlIO limitsVar statsVar posVar = interpret_ $ \case
  CheckOrder req -> liftIO $ do
    now <- getCurrentTime
    atomically $ do
      limits    <- readTVar limitsVar
      stats     <- readTVar statsVar
      positions <- readTVar posVar
      pure $ evaluateRisk limits stats positions now req
  GetRiskLimits ->
    liftIO $ atomically $ readTVar limitsVar
  UpdateRiskLimits newLimits ->
    liftIO $ atomically $ writeTVar limitsVar newLimits
```

- [ ] **Step 2: Implement OrderManager IO interpreter**

Add to `src/Hypell/Interpreter/OrderManager.hs`:

```haskell
-- Add to existing module:
import Control.Concurrent.STM
import Data.Time.Clock (getCurrentTime)

runOrderManagerIO
  :: (Exchange :> es, IOE :> es)
  => TVar (Map.Map OrderId Order)
  -> Eff (OrderManager : es) a -> Eff es a
runOrderManagerIO ordersVar = interpret_ $ \case
  SubmitOrder req -> do
    resp <- placeOrder req
    now  <- liftIO getCurrentTime
    let (oid, status) = case resp of
          OrderResting i   -> (i, OsResting)
          OrderFilled s p  -> (0, OsFilled s p)
          OrderError t     -> (0, OsRejected t)
    let mo = ManagedOrder oid req status now
    liftIO $ atomically $ modifyTVar' ordersVar (Map.insert oid (orderFromManaged mo))
    pure mo
  TrackOrder oid -> do
    orders <- liftIO $ atomically $ readTVar ordersVar
    pure $ maybe OsCancelled oStatus (Map.lookup oid orders)
  CancelManaged oid -> do
    _ <- cancelOrder (CancelById (SpotCoin "") oid)
    liftIO $ atomically $ modifyTVar' ordersVar (Map.delete oid)

orderFromManaged :: ManagedOrder -> Order
orderFromManaged mo = Order
  { oId = moId mo, oRequest = moRequest mo, oStatus = moStatus mo
  , oFilledSz = 0, oAvgPrice = Nothing, oCreatedAt = moCreatedAt mo
  }
```

- [ ] **Step 3: Implement AlgoExec IO interpreter**

Add to `src/Hypell/Interpreter/AlgoExec.hs`:

```haskell
-- Add to existing module, or create IO variant:
import Control.Concurrent (threadDelay)
import Control.Concurrent.Async (async, cancel)
import Control.Concurrent.STM
import Hypell.Algo.TWAP (computeSlices)
import Hypell.Algo.Iceberg (computeIcebergOrder)

runAlgoExecIO
  :: (IOE :> es)
  => TBQueue TradeAction  -- action queue for engine to execute
  -> Eff (AlgoExec : es) a -> Eff es a
runAlgoExecIO actionQueue = interpret_ $ \case
  RunTWAP params -> liftIO $ do
    statusVar <- newTVarIO (AlgoRunning 0)
    thread <- async $ twapLoop params statusVar actionQueue
    pure AlgoHandle
      { ahId = "twap-" <> twCoin params
      , ahThread = thread, ahParams = AlgoTWAP params, ahStatus = statusVar
      }
  RunIceberg params -> liftIO $ do
    statusVar <- newTVarIO (AlgoRunning 0)
    thread <- async $ icebergLoop params statusVar actionQueue
    pure AlgoHandle
      { ahId = "iceberg-" <> ibCoin params
      , ahThread = thread, ahParams = AlgoIceberg params, ahStatus = statusVar
      }
  CancelAlgo handle -> liftIO $ do
    cancel (ahThread handle)
    atomically $ writeTVar (ahStatus handle) AlgoCancelled

twapLoop :: TWAPParams -> TVar AlgoStatus -> TBQueue TradeAction -> IO ()
twapLoop params statusVar queue = do
  let slices = computeSlices params
  go slices 0
  where
    go [] filled = atomically $ writeTVar statusVar (AlgoCompleted filled)
    go (sz:rest) filled = do
      let order = OrderRequest
            { orCoin = twCoin params, orSide = twSide params
            , orSize = sz, orType = Market, orCloid = Nothing
            }
      atomically $ writeTBQueue queue (ActionPlace order)
      atomically $ writeTVar statusVar (AlgoRunning (filled + sz))
      threadDelay (twIntervalMs params * 1000)
      go rest (filled + sz)

icebergLoop :: IcebergParams -> TVar AlgoStatus -> TBQueue TradeAction -> IO ()
icebergLoop params statusVar queue = go 0
  where
    go filled
      | filled >= ibTotalSize params =
          atomically $ writeTVar statusVar (AlgoCompleted filled)
      | otherwise = do
          let order = computeIcebergOrder params filled
          atomically $ writeTBQueue queue (ActionPlace order)
          atomically $ writeTVar statusVar (AlgoRunning filled)
          -- Wait for fill notification (simplified: use delay)
          threadDelay 5_000_000  -- 5s poll; real impl listens for EventOrderFill
          go (filled + orSize order)
```

- [ ] **Step 4: Verify compiles**

Run: `cabal build lib:hypell`
Expected: Compiles

- [ ] **Step 5: Commit**

```bash
git add src/Hypell/Interpreter/RiskControl.hs src/Hypell/Interpreter/OrderManager.hs src/Hypell/Interpreter/AlgoExec.hs
git commit -m "feat: IO interpreters for RiskControl, OrderManager, AlgoExec"
```

---

### Task 15: Engine (`Engine.hs`)

**Files:**
- Create: `src/Hypell/Engine.hs`

- [ ] **Step 1: Implement Engine**

```haskell
module Hypell.Engine
  ( EngineEnv(..)
  , initEnv
  , runEngine
  , eventLoop
  , executeAction
  ) where

import Control.Concurrent (threadDelay)
import Control.Concurrent.Async (withAsync)
import Control.Concurrent.STM
import Data.Map.Strict qualified as Map
import Data.Time (getCurrentTime, utctDay)
import Data.Void (absurd)
import Effectful
import Effectful.Dispatch.Dynamic
import Hypell.Types
import Hypell.Config (Config(..))
import Hypell.Effect.Log
import Hypell.Effect.Exchange
import Hypell.Effect.MarketData
import Hypell.Effect.Account
import Hypell.Effect.RiskControl
import Hypell.Effect.OrderManager
import Hypell.Effect.AlgoExec
import Hypell.Strategy (Strategy(..))
import Hypell.Api.Rest (RestClient, newRestClient)
import Hypell.Api.WebSocket (WsClient, connectWs, wsListenerLoop)
import qualified Network.WebSockets as WS

data EngineEnv = EngineEnv
  { eeConfig     :: Config
  , eeEventBus   :: TBQueue MarketEvent
  , eeRestClient :: RestClient
  , eeWsClient   :: WsClient
  , eeRiskLimits :: TVar RiskLimits
  , eePositions  :: TVar (Map.Map Coin TokenBalance)
  , eeOpenOrders :: TVar (Map.Map OrderId Order)
  , eeDailyStats :: TVar DailyStats
  }

initEnv :: Config -> IO EngineEnv
initEnv cfg = do
  eventBus   <- newTBQueueIO (fromIntegral $ ecEventQueueSize $ cfgEngine cfg)
  restClient <- newRestClient (cfgApiUrl cfg) (cfgPrivateKey cfg)
  wsClient   <- connectWs (cfgWsUrl cfg) eventBus
  riskVar    <- newTVarIO (cfgRisk cfg)
  posVar     <- newTVarIO Map.empty
  ordersVar  <- newTVarIO Map.empty
  now        <- getCurrentTime
  statsVar   <- newTVarIO DailyStats
    { dsTotalVolume   = 0
    , dsTotalTrades   = 0
    , dsLastOrderTime = Nothing
    , dsDate          = utctDay now
    }
  pure EngineEnv
    { eeConfig     = cfg
    , eeEventBus   = eventBus
    , eeRestClient = restClient
    , eeWsClient   = wsClient
    , eeRiskLimits = riskVar
    , eePositions  = posVar
    , eeOpenOrders = ordersVar
    , eeDailyStats = statsVar
    }

-- Timer loop: push EventTimer to event bus
timerLoop :: TBQueue MarketEvent -> Int -> IO ()
timerLoop bus intervalMs = go
  where
    go = do
      threadDelay (intervalMs * 1000)
      now <- getCurrentTime
      atomically $ writeTBQueue bus (EventTimer now)
      go

-- Order tracker loop: poll order status
orderTrackerLoop :: EngineEnv -> IO ()
orderTrackerLoop env = go
  where
    intervalMs = ecOrderPollIntervalMs $ cfgEngine $ eeConfig env
    go = do
      threadDelay (intervalMs * 1000)
      -- TODO: REST query open orders, diff against eeOpenOrders,
      -- emit EventOrderFill / EventOrderCancel
      go

-- Main event loop
eventLoop
  :: ( Strategy s, Exchange :> es, MarketData :> es, Account :> es
     , RiskControl :> es, OrderManager :> es, AlgoExec :> es
     , Log :> es, IOE :> es )
  => EngineEnv -> s -> Eff es ()
eventLoop env strategy = do
  event <- liftIO $ atomically $ readTBQueue (eeEventBus env)
  (strategy', actions) <- onEvent strategy event
  mapM_ (executeAction env) actions
  eventLoop env strategy'

executeAction
  :: ( Exchange :> es, RiskControl :> es, OrderManager :> es
     , AlgoExec :> es, Log :> es, IOE :> es )
  => EngineEnv -> TradeAction -> Eff es ()
executeAction _env = \case
  ActionPlace req -> do
    riskResult <- checkOrder req
    case riskResult of
      RiskPass     -> void $ submitOrder req
      RiskReject r -> log $ "Risk rejected: " <> r
  ActionCancel req   -> void $ cancelOrder req
  ActionCancelAll    -> cancelAll
  ActionAlgoTWAP p   -> void $ runTWAP p
  ActionAlgoIceberg p -> void $ runIceberg p
  ActionLog msg      -> log msg

-- Top-level entry point
runEngine :: Strategy s => Config -> s -> IO ()
runEngine cfg initialStrategy = do
  env <- initEnv cfg
  -- TODO: Wire up full effect stack with IO interpreters
  -- and launch concurrent threads with withAsync
  putStrLn "Engine started (TODO: full wiring)"
```

- [ ] **Step 2: Verify compiles**

Run: `cabal build lib:hypell`
Expected: Compiles

- [ ] **Step 3: Commit**

```bash
git add src/Hypell/Engine.hs
git commit -m "feat: execution engine with event loop, initEnv, and executeAction"
```

---

## Chunk 6: Algo Execution + Example Strategy

### Task 16: TWAP algorithm

**Files:**
- Create: `src/Hypell/Algo/TWAP.hs`
- Create: `test/Test/Hypell/AlgoTest.hs`

- [ ] **Step 1: Write TWAP tests**

```haskell
module Test.Hypell.AlgoTest (tests) where

import Test.Tasty
import Test.Tasty.HUnit
import Data.Scientific (scientific)
import Hypell.Types
import Hypell.Algo.TWAP (computeSlices)

tests :: TestTree
tests = testGroup "Algo"
  [ testGroup "TWAP"
    [ testCase "splits evenly" $ do
        let params = TWAPParams
              { twCoin = SpotCoin "HYPE/USDC", twSide = Buy
              , twTotalSize = scientific 100 0, twSlices = 4
              , twIntervalMs = 1000
              }
        let slices = computeSlices params
        length slices @?= 4
        all (== scientific 25 0) slices @?= True

    , testCase "handles remainder" $ do
        let params = TWAPParams
              { twCoin = SpotCoin "HYPE/USDC", twSide = Buy
              , twTotalSize = scientific 100 0, twSlices = 3
              , twIntervalMs = 1000
              }
        let slices = computeSlices params
        length slices @?= 3
        sum slices @?= scientific 100 0
    ]
  ]
```

- [ ] **Step 2: Wire into Spec.hs**

Add `import qualified Test.Hypell.AlgoTest` and include `Test.Hypell.AlgoTest.tests` in the test group.

- [ ] **Step 3: Run tests to verify they fail**

Run: `cabal test`
Expected: FAIL — module not found

- [ ] **Step 4: Implement TWAP**

```haskell
module Hypell.Algo.TWAP
  ( computeSlices
  ) where

import Data.Scientific (Scientific)
import Hypell.Types

-- Compute slice sizes for TWAP execution
computeSlices :: TWAPParams -> [Scientific]
computeSlices params =
  let n     = twSlices params
      total = twTotalSize params
      base  = total / fromIntegral n
      remainder = total - base * fromIntegral n
      -- Put remainder in last slice
      slices = replicate (n - 1) base ++ [base + remainder]
  in slices
```

- [ ] **Step 5: Run tests**

Run: `cabal test`
Expected: All tests PASS

- [ ] **Step 6: Commit**

```bash
git add src/Hypell/Algo/TWAP.hs test/Test/Hypell/AlgoTest.hs test/Spec.hs
git commit -m "feat: TWAP slice computation with tests"
```

---

### Task 17: Iceberg algorithm

**Files:**
- Create: `src/Hypell/Algo/Iceberg.hs`

- [ ] **Step 1: Add Iceberg tests to AlgoTest.hs**

```haskell
-- Add to Test.Hypell.AlgoTest
import Hypell.Algo.Iceberg (computeIcebergOrder)

-- Add to tests group:
, testGroup "Iceberg"
    [ testCase "visible size capped at total remaining" $ do
        let params = IcebergParams
              { ibCoin = SpotCoin "HYPE/USDC", ibSide = Buy
              , ibTotalSize = scientific 30 0
              , ibVisibleSize = scientific 100 0
              , ibLimitPrice = scientific 25 0
              }
        let order = computeIcebergOrder params 0
        orSize order @?= scientific 30 0  -- capped at remaining

    , testCase "normal visible slice" $ do
        let params = IcebergParams
              { ibCoin = SpotCoin "HYPE/USDC", ibSide = Buy
              , ibTotalSize = scientific 1000 0
              , ibVisibleSize = scientific 100 0
              , ibLimitPrice = scientific 25 0
              }
        let order = computeIcebergOrder params 0
        orSize order @?= scientific 100 0
    ]
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cabal test`
Expected: FAIL — module not found

- [ ] **Step 3: Implement Iceberg**

```haskell
module Hypell.Algo.Iceberg
  ( computeIcebergOrder
  ) where

import Data.Scientific (Scientific)
import Hypell.Types

-- Compute next visible order for iceberg execution
computeIcebergOrder :: IcebergParams -> Scientific -> OrderRequest
computeIcebergOrder params filledSoFar =
  let remaining = ibTotalSize params - filledSoFar
      sz = min (ibVisibleSize params) remaining
  in OrderRequest
    { orCoin  = ibCoin params
    , orSide  = ibSide params
    , orSize  = sz
    , orType  = Limit (ibLimitPrice params) GTC
    , orCloid = Nothing
    }
```

- [ ] **Step 4: Run tests**

Run: `cabal test`
Expected: All tests PASS

- [ ] **Step 5: Commit**

```bash
git add src/Hypell/Algo/Iceberg.hs test/Test/Hypell/AlgoTest.hs
git commit -m "feat: Iceberg order computation with tests"
```

---

### Task 18: Example strategy (`SimpleGrid`)

**Files:**
- Create: `examples/SimpleGrid.hs`

- [ ] **Step 1: Implement SimpleGrid example**

```haskell
module Main where

import Data.Map.Strict qualified as Map
import Data.Scientific (Scientific, scientific)
import Data.Text (Text)
import Effectful
import Hypell.Types
import Hypell.Strategy
import Hypell.Effect.Log (Log, log)
import Hypell.Effect.MarketData (MarketData)
import Hypell.Effect.Account (Account, getBalances)
import Hypell.Effect.OrderManager (OrderManager)

data GridStrategy = GridStrategy
  { gsGridLevels  :: [(Scientific, Scientific)]  -- (price, size)
  , gsActiveOrders :: Map.Map Scientific OrderId
  } deriving stock (Show)

instance Strategy GridStrategy where
  strategyName _ = "simple-grid"

  initStrategy s = do
    log "Grid strategy initialized"
    pure s

  onEvent s (EventOrderFill oid fillSz fillPx) = do
    log $ "Fill: " <> tshow fillPx <> " x " <> tshow fillSz
    -- On fill, place opposite order
    let oppSide = if any (\(_, oId) -> oId == oid) (Map.toList $ gsActiveOrders s)
                  then Sell else Buy
    pure (s, [ActionPlace OrderRequest
      { orCoin  = SpotCoin "HYPE/USDC"
      , orSide  = oppSide
      , orSize  = fillSz
      , orType  = Limit fillPx GTC
      , orCloid = Nothing
      }])

  onEvent s (EventTimer _) = do
    bals <- getBalances
    log $ "Heartbeat, balances: " <> tshow (length bals)
    pure (s, [])

  onEvent s _ = pure (s, [])

  onShutdown _ = do
    log "Grid strategy shutting down"
    pure ()

tshow :: Show a => a -> Text
tshow = Data.Text.pack . show

main :: IO ()
main = do
  let strategy = GridStrategy
        { gsGridLevels   = [(scientific 24 0, scientific 10 0), (scientific 26 0, scientific 10 0)]
        , gsActiveOrders = Map.empty
        }
  putStrLn $ "Strategy: " <> show (strategyName strategy)
  putStrLn "TODO: integrate with runEngine"
```

- [ ] **Step 2: Verify compiles**

Run: `cabal build exe:simple-grid`
Expected: Compiles

- [ ] **Step 3: Commit**

```bash
git add examples/SimpleGrid.hs
git commit -m "feat: SimpleGrid example strategy"
```

---

### Task 19: Final integration — wire `runEngine`

**Files:**
- Modify: `src/Hypell/Engine.hs`
- Modify: `app/Main.hs`

- [ ] **Step 1: Complete `runEngine` wiring in `Engine.hs`**

Update the `runEngine` function to wire all IO interpreters with `withAsync` for concurrent threads:

```haskell
runEngine :: Strategy s => Config -> s -> IO ()
runEngine cfg initialStrategy = do
  env <- initEnv cfg
  algoQueue <- newTBQueueIO 256
  let logAction = mkLogAction (cfgLogLevel cfg)
  runEff
    . runLog logAction
    . runAlgoExecIO algoQueue
    . runRiskControlIO (eeRiskLimits env) (eeDailyStats env) (eePositions env)
    . runExchangeIO (eeRestClient env) (eeOpenOrders env)
    . runOrderManagerIO (eeOpenOrders env)
    . runMarketDataIO (eeRestClient env) (eeWsClient env)
    . runAccountIO (eeRestClient env) "TODO_WALLET_ADDR"
    $ do
      log "Engine starting..."
      strategy' <- initStrategy initialStrategy
      liftIO $ withAsync (wsListenerLoop (eeWsClient env)) $ \_ ->
        withAsync (orderTrackerLoop env) $ \_ ->
          withAsync (timerLoop (eeEventBus env) (ecHeartbeatIntervalMs $ cfgEngine cfg)) $ \_ ->
            -- TODO: run eventLoop inside the effect stack
            -- This requires threading the Eff monad into the IO callback
            pure ()
      log "Engine stopped"
```

Note: Full threading of `Eff` into `withAsync` callbacks requires `Effectful.Concurrent`. This will be refined during testnet integration.

- [ ] **Step 2: Update `app/Main.hs`**

```haskell
module Main where

import System.Environment (getArgs)
import Hypell.Config (loadConfig)
import Hypell.Engine (runEngine)

main :: IO ()
main = do
  args <- getArgs
  let configPath = case args of
        (p:_) -> p
        []    -> "config/example.yaml"
  putStrLn $ "Loading config from: " <> configPath
  -- TODO: load config and run engine with a strategy
  -- cfg <- loadConfig configPath
  -- runEngine cfg someStrategy
  putStrLn "hypell: use examples/SimpleGrid.hs for now"
```

- [ ] **Step 3: Verify everything compiles**

Run: `cabal build all`
Expected: Compiles

- [ ] **Step 4: Run all tests**

Run: `cabal test`
Expected: All tests PASS

- [ ] **Step 5: Commit**

```bash
git add src/Hypell/Engine.hs app/Main.hs
git commit -m "feat: wire runEngine and Main entry point"
```

---

### Task 20: Final re-export and cleanup

**Files:**
- Modify: `src/Hypell.hs`

- [ ] **Step 1: Update Hypell.hs re-exports**

```haskell
module Hypell
  ( -- * Types
    module Hypell.Types
    -- * Config
  , module Hypell.Config
    -- * Effects
  , module Hypell.Effect.Exchange
  , module Hypell.Effect.MarketData
  , module Hypell.Effect.Account
  , module Hypell.Effect.RiskControl
  , module Hypell.Effect.OrderManager
  , module Hypell.Effect.AlgoExec
  , module Hypell.Effect.Log
    -- * Strategy
  , module Hypell.Strategy
    -- * Risk
  , module Hypell.Risk
    -- * Engine
  , module Hypell.Engine
  ) where

import Hypell.Types
import Hypell.Config
import Hypell.Effect.Exchange
import Hypell.Effect.MarketData
import Hypell.Effect.Account
import Hypell.Effect.RiskControl
import Hypell.Effect.OrderManager
import Hypell.Effect.AlgoExec
import Hypell.Effect.Log
import Hypell.Strategy
import Hypell.Risk
import Hypell.Engine
```

- [ ] **Step 2: Final build and test**

Run: `cabal build all && cabal test`
Expected: Compiles and all tests PASS

- [ ] **Step 3: Commit**

```bash
git add src/Hypell.hs
git commit -m "feat: complete Hypell re-export module"
```
