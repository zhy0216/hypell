{-# LANGUAGE StrictData #-}

module Hypell.Types
  ( -- * Identifiers
    OrderId
  , ClientOrderId
  , Coin(..)

    -- * Enums
  , Side(..)
  , TimeInForce(..)
  , OrderType(..)
  , OrderStatus(..)
  , LogLevel(..)
  , Network(..)

    -- * Orders
  , OrderRequest(..)
  , OrderResponse(..)
  , CancelRequest(..)
  , CancelResponse(..)
  , Order(..)

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
  , EngineConfig(..)
  , DailyStats(..)
  ) where

import Data.Aeson hiding (Error)
import Data.Aeson.Types (Parser)
import Data.Map.Strict (Map)
import Data.Scientific (Scientific)
import Data.Text (Text)
import Data.Time (UTCTime)
import Data.Word (Word64)
import GHC.Generics (Generic)

-- ---------------------------------------------------------------------------
-- Identifiers
-- ---------------------------------------------------------------------------

type OrderId       = Word64
type ClientOrderId = Text

newtype Coin = Coin { unCoin :: Text }
  deriving stock   (Eq, Ord, Show, Generic)
  deriving newtype (FromJSON, ToJSON, FromJSONKey, ToJSONKey)

-- ---------------------------------------------------------------------------
-- Side
-- ---------------------------------------------------------------------------

data Side = Buy | Sell
  deriving stock (Eq, Ord, Show, Generic)

instance ToJSON Side where
  toJSON Buy  = String "B"
  toJSON Sell = String "A"

instance FromJSON Side where
  parseJSON = withText "Side" $ \case
    "B" -> pure Buy
    "A" -> pure Sell
    _   -> fail "Expected \"B\" or \"A\""

-- ---------------------------------------------------------------------------
-- TimeInForce
-- ---------------------------------------------------------------------------

data TimeInForce = GTC | IOC | ALO
  deriving stock (Eq, Ord, Show, Generic)

instance ToJSON TimeInForce where
  toJSON GTC = String "Gtc"
  toJSON IOC = String "Ioc"
  toJSON ALO = String "Alo"

instance FromJSON TimeInForce where
  parseJSON = withText "TimeInForce" $ \case
    "Gtc" -> pure GTC
    "Ioc" -> pure IOC
    "Alo" -> pure ALO
    _     -> fail "Expected Gtc, Ioc, or Alo"

-- ---------------------------------------------------------------------------
-- OrderType
-- ---------------------------------------------------------------------------

data OrderType
  = Limit  { limitPrice :: Scientific, limitTif :: TimeInForce }
  | Market
  deriving stock (Eq, Show, Generic)

instance ToJSON OrderType where
  toJSON Market = object ["type" .= String "market"]
  toJSON (Limit p tif) = object
    [ "type"  .= String "limit"
    , "price" .= p
    , "tif"   .= tif
    ]

instance FromJSON OrderType where
  parseJSON = withObject "OrderType" $ \o -> do
    t <- o .: "type" :: Parser Text
    case t of
      "market" -> pure Market
      "limit"  -> Limit <$> o .: "price" <*> o .: "tif"
      _        -> fail "Expected \"market\" or \"limit\""

-- ---------------------------------------------------------------------------
-- OrderStatus
-- ---------------------------------------------------------------------------

data OrderStatus
  = Pending
  | Open
  | PartiallyFilled
  | Filled
  | Cancelled
  | Rejected
  deriving stock (Eq, Ord, Show, Generic)

instance ToJSON OrderStatus where
  toJSON = \case
    Pending         -> String "pending"
    Open            -> String "open"
    PartiallyFilled -> String "partiallyFilled"
    Filled          -> String "filled"
    Cancelled       -> String "cancelled"
    Rejected        -> String "rejected"

instance FromJSON OrderStatus where
  parseJSON = withText "OrderStatus" $ \case
    "pending"         -> pure Pending
    "open"            -> pure Open
    "partiallyFilled" -> pure PartiallyFilled
    "filled"          -> pure Filled
    "cancelled"       -> pure Cancelled
    "rejected"        -> pure Rejected
    _                 -> fail "Invalid OrderStatus"

-- ---------------------------------------------------------------------------
-- OrderRequest / OrderResponse
-- ---------------------------------------------------------------------------

data OrderRequest = OrderRequest
  { orCoin      :: Coin
  , orSide      :: Side
  , orSize      :: Scientific
  , orOrderType :: OrderType
  , orClientId  :: Maybe ClientOrderId
  } deriving stock (Eq, Show, Generic)

instance ToJSON OrderRequest where
  toJSON r = object
    [ "coin"      .= orCoin r
    , "side"      .= orSide r
    , "size"      .= orSize r
    , "orderType" .= orOrderType r
    , "clientId"  .= orClientId r
    ]

instance FromJSON OrderRequest where
  parseJSON = withObject "OrderRequest" $ \o ->
    OrderRequest
      <$> o .:  "coin"
      <*> o .:  "side"
      <*> o .:  "size"
      <*> o .:  "orderType"
      <*> o .:? "clientId"

data OrderResponse = OrderResponse
  { orspStatus  :: Text
  , orspOrderId :: Maybe OrderId
  } deriving stock (Eq, Show, Generic)

instance ToJSON OrderResponse where
  toJSON r = object
    [ "status"  .= orspStatus r
    , "orderId" .= orspOrderId r
    ]

instance FromJSON OrderResponse where
  parseJSON = withObject "OrderResponse" $ \o ->
    OrderResponse <$> o .: "status" <*> o .:? "orderId"

-- ---------------------------------------------------------------------------
-- CancelRequest / CancelResponse
-- ---------------------------------------------------------------------------

data CancelRequest = CancelRequest
  { crCoin    :: Coin
  , crOrderId :: OrderId
  } deriving stock (Eq, Show, Generic)

instance ToJSON CancelRequest where
  toJSON r = object ["coin" .= crCoin r, "orderId" .= crOrderId r]

instance FromJSON CancelRequest where
  parseJSON = withObject "CancelRequest" $ \o ->
    CancelRequest <$> o .: "coin" <*> o .: "orderId"

data CancelResponse = CancelResponse
  { crespStatus :: Text
  } deriving stock (Eq, Show, Generic)

instance ToJSON CancelResponse where
  toJSON r = object ["status" .= crespStatus r]

instance FromJSON CancelResponse where
  parseJSON = withObject "CancelResponse" $ \o ->
    CancelResponse <$> o .: "status"

-- ---------------------------------------------------------------------------
-- Order
-- ---------------------------------------------------------------------------

data Order = Order
  { orderId       :: OrderId
  , orderCoin     :: Coin
  , orderSide     :: Side
  , orderSize     :: Scientific
  , orderFilled   :: Scientific
  , orderPrice    :: Maybe Scientific
  , orderStatus   :: OrderStatus
  , orderClientId :: Maybe ClientOrderId
  , orderTime     :: UTCTime
  } deriving stock (Eq, Show, Generic)

instance ToJSON Order where
  toJSON o = object
    [ "orderId"  .= orderId o
    , "coin"     .= orderCoin o
    , "side"     .= orderSide o
    , "size"     .= orderSize o
    , "filled"   .= orderFilled o
    , "price"    .= orderPrice o
    , "status"   .= orderStatus o
    , "clientId" .= orderClientId o
    , "time"     .= orderTime o
    ]

instance FromJSON Order where
  parseJSON = withObject "Order" $ \o ->
    Order
      <$> o .:  "orderId"
      <*> o .:  "coin"
      <*> o .:  "side"
      <*> o .:  "size"
      <*> o .:  "filled"
      <*> o .:? "price"
      <*> o .:  "status"
      <*> o .:? "clientId"
      <*> o .:  "time"

-- ---------------------------------------------------------------------------
-- Market data types
-- ---------------------------------------------------------------------------

data OrderBook = OrderBook
  { obBids :: [(Scientific, Scientific)]  -- (price, size)
  , obAsks :: [(Scientific, Scientific)]
  , obTime :: UTCTime
  } deriving stock (Eq, Show, Generic)

instance ToJSON OrderBook where
  toJSON ob = object
    [ "bids" .= obBids ob
    , "asks" .= obAsks ob
    , "time" .= obTime ob
    ]

instance FromJSON OrderBook where
  parseJSON = withObject "OrderBook" $ \o ->
    OrderBook <$> o .: "bids" <*> o .: "asks" <*> o .: "time"

data Trade = Trade
  { trdCoin  :: Coin
  , trdSide  :: Side
  , trdPrice :: Scientific
  , trdSize  :: Scientific
  , trdTime  :: UTCTime
  } deriving stock (Eq, Show, Generic)

instance ToJSON Trade where
  toJSON t = object
    [ "coin"  .= trdCoin t
    , "side"  .= trdSide t
    , "price" .= trdPrice t
    , "size"  .= trdSize t
    , "time"  .= trdTime t
    ]

instance FromJSON Trade where
  parseJSON = withObject "Trade" $ \o ->
    Trade <$> o .: "coin" <*> o .: "side" <*> o .: "price" <*> o .: "size" <*> o .: "time"

data SpotAssetCtx = SpotAssetCtx
  { sacMarkPrice   :: Scientific
  , sacMidPrice    :: Maybe Scientific
  , sacPrevDayPx   :: Scientific
  , sacDayNtlVlm   :: Scientific
  , sacCircSupply  :: Scientific
  } deriving stock (Eq, Show, Generic)

instance ToJSON SpotAssetCtx where
  toJSON c = object
    [ "markPrice"  .= sacMarkPrice c
    , "midPrice"   .= sacMidPrice c
    , "prevDayPx"  .= sacPrevDayPx c
    , "dayNtlVlm"  .= sacDayNtlVlm c
    , "circSupply" .= sacCircSupply c
    ]

instance FromJSON SpotAssetCtx where
  parseJSON = withObject "SpotAssetCtx" $ \o ->
    SpotAssetCtx
      <$> o .:  "markPrice"
      <*> o .:? "midPrice"
      <*> o .:  "prevDayPx"
      <*> o .:  "dayNtlVlm"
      <*> o .:  "circSupply"

data TokenInfo = TokenInfo
  { tiName     :: Text
  , tiIndex    :: Int
  , tiTokenId  :: Text
  } deriving stock (Eq, Show, Generic)

instance ToJSON TokenInfo where
  toJSON t = object
    [ "name"    .= tiName t
    , "index"   .= tiIndex t
    , "tokenId" .= tiTokenId t
    ]

instance FromJSON TokenInfo where
  parseJSON = withObject "TokenInfo" $ \o ->
    TokenInfo <$> o .: "name" <*> o .: "index" <*> o .: "tokenId"

data SpotPair = SpotPair
  { spName       :: Text
  , spTokens     :: (Int, Int)
  , spIndex      :: Int
  , spIsCanonical :: Bool
  } deriving stock (Eq, Show, Generic)

instance ToJSON SpotPair where
  toJSON p = object
    [ "name"        .= spName p
    , "tokens"      .= spTokens p
    , "index"       .= spIndex p
    , "isCanonical" .= spIsCanonical p
    ]

instance FromJSON SpotPair where
  parseJSON = withObject "SpotPair" $ \o ->
    SpotPair <$> o .: "name" <*> o .: "tokens" <*> o .: "index" <*> o .: "isCanonical"

data SpotMeta = SpotMeta
  { smTokens :: [TokenInfo]
  , smPairs  :: [SpotPair]
  } deriving stock (Eq, Show, Generic)

instance ToJSON SpotMeta where
  toJSON m = object
    [ "tokens" .= smTokens m
    , "pairs"  .= smPairs m
    ]

instance FromJSON SpotMeta where
  parseJSON = withObject "SpotMeta" $ \o ->
    SpotMeta <$> o .: "tokens" <*> o .: "pairs"

-- ---------------------------------------------------------------------------
-- Account types
-- ---------------------------------------------------------------------------

data TokenBalance = TokenBalance
  { tbCoin   :: Coin
  , tbTotal  :: Scientific
  , tbHold   :: Scientific
  } deriving stock (Eq, Show, Generic)

instance ToJSON TokenBalance where
  toJSON b = object
    [ "coin"  .= tbCoin b
    , "total" .= tbTotal b
    , "hold"  .= tbHold b
    ]

instance FromJSON TokenBalance where
  parseJSON = withObject "TokenBalance" $ \o ->
    TokenBalance <$> o .: "coin" <*> o .: "total" <*> o .: "hold"

data UserTrade = UserTrade
  { utCoin     :: Coin
  , utSide     :: Side
  , utPrice    :: Scientific
  , utSize     :: Scientific
  , utFee      :: Scientific
  , utTime     :: UTCTime
  , utOrderId  :: OrderId
  } deriving stock (Eq, Show, Generic)

instance ToJSON UserTrade where
  toJSON t = object
    [ "coin"    .= utCoin t
    , "side"    .= utSide t
    , "price"   .= utPrice t
    , "size"    .= utSize t
    , "fee"     .= utFee t
    , "time"    .= utTime t
    , "orderId" .= utOrderId t
    ]

instance FromJSON UserTrade where
  parseJSON = withObject "UserTrade" $ \o ->
    UserTrade
      <$> o .: "coin"
      <*> o .: "side"
      <*> o .: "price"
      <*> o .: "size"
      <*> o .: "fee"
      <*> o .: "time"
      <*> o .: "orderId"

-- ---------------------------------------------------------------------------
-- Risk types
-- ---------------------------------------------------------------------------

data RiskLimits = RiskLimits
  { rlMaxOrderSize    :: Scientific
  , rlMaxDailyVolume  :: Scientific
  , rlCooldownMs      :: Int
  , rlMaxPositionSize :: Map Coin Scientific
  } deriving stock (Eq, Show, Generic)

instance ToJSON RiskLimits where
  toJSON r = object
    [ "maxOrderSize"    .= rlMaxOrderSize r
    , "maxDailyVolume"  .= rlMaxDailyVolume r
    , "cooldownMs"      .= rlCooldownMs r
    , "maxPositionSize" .= rlMaxPositionSize r
    ]

instance FromJSON RiskLimits where
  parseJSON = withObject "RiskLimits" $ \o ->
    RiskLimits
      <$> o .: "maxOrderSize"
      <*> o .: "maxDailyVolume"
      <*> o .: "cooldownMs"
      <*> o .: "maxPositionSize"

data RiskResult
  = RiskAllow
  | RiskReject Text
  deriving stock (Eq, Show, Generic)

instance ToJSON RiskResult where
  toJSON RiskAllow       = object ["result" .= String "allow"]
  toJSON (RiskReject r)  = object ["result" .= String "reject", "reason" .= r]

instance FromJSON RiskResult where
  parseJSON = withObject "RiskResult" $ \o -> do
    r <- o .: "result" :: Parser Text
    case r of
      "allow"  -> pure RiskAllow
      "reject" -> RiskReject <$> o .: "reason"
      _        -> fail "Expected allow or reject"

-- ---------------------------------------------------------------------------
-- Algo types
-- ---------------------------------------------------------------------------

data TWAPParams = TWAPParams
  { twapCoin         :: Coin
  , twapSide         :: Side
  , twapTotalSize    :: Scientific
  , twapDurationSecs :: Int
  , twapNumSlices    :: Int
  , twapLimitPrice   :: Maybe Scientific
  } deriving stock (Eq, Show, Generic)

instance ToJSON TWAPParams where
  toJSON p = object
    [ "coin"         .= twapCoin p
    , "side"         .= twapSide p
    , "totalSize"    .= twapTotalSize p
    , "durationSecs" .= twapDurationSecs p
    , "numSlices"    .= twapNumSlices p
    , "limitPrice"   .= twapLimitPrice p
    ]

instance FromJSON TWAPParams where
  parseJSON = withObject "TWAPParams" $ \o ->
    TWAPParams
      <$> o .:  "coin"
      <*> o .:  "side"
      <*> o .:  "totalSize"
      <*> o .:  "durationSecs"
      <*> o .:  "numSlices"
      <*> o .:? "limitPrice"

data IcebergParams = IcebergParams
  { iceCoin       :: Coin
  , iceSide       :: Side
  , iceTotalSize  :: Scientific
  , iceShowSize   :: Scientific
  , iceLimitPrice :: Scientific
  } deriving stock (Eq, Show, Generic)

instance ToJSON IcebergParams where
  toJSON p = object
    [ "coin"       .= iceCoin p
    , "side"       .= iceSide p
    , "totalSize"  .= iceTotalSize p
    , "showSize"   .= iceShowSize p
    , "limitPrice" .= iceLimitPrice p
    ]

instance FromJSON IcebergParams where
  parseJSON = withObject "IcebergParams" $ \o ->
    IcebergParams
      <$> o .: "coin"
      <*> o .: "side"
      <*> o .: "totalSize"
      <*> o .: "showSize"
      <*> o .: "limitPrice"

data AlgoParams
  = AlgoTWAP    TWAPParams
  | AlgoIceberg IcebergParams
  deriving stock (Eq, Show, Generic)

instance ToJSON AlgoParams where
  toJSON (AlgoTWAP p)    = object ["algo" .= String "twap",    "params" .= p]
  toJSON (AlgoIceberg p) = object ["algo" .= String "iceberg", "params" .= p]

instance FromJSON AlgoParams where
  parseJSON = withObject "AlgoParams" $ \o -> do
    algo <- o .: "algo" :: Parser Text
    case algo of
      "twap"    -> AlgoTWAP    <$> o .: "params"
      "iceberg" -> AlgoIceberg <$> o .: "params"
      _         -> fail "Expected twap or iceberg"

data AlgoStatus
  = AlgoRunning  { asFilledSize :: Scientific }
  | AlgoComplete { asTotalFilled :: Scientific, asAvgPrice :: Scientific }
  | AlgoStopped  { asReason :: Text, asPartialFill :: Scientific }
  deriving stock (Eq, Show, Generic)

instance ToJSON AlgoStatus where
  toJSON (AlgoRunning f) = object
    ["status" .= String "running", "filledSize" .= f]
  toJSON (AlgoComplete tf ap') = object
    ["status" .= String "complete", "totalFilled" .= tf, "avgPrice" .= ap']
  toJSON (AlgoStopped r pf) = object
    ["status" .= String "stopped", "reason" .= r, "partialFill" .= pf]

instance FromJSON AlgoStatus where
  parseJSON = withObject "AlgoStatus" $ \o -> do
    s <- o .: "status" :: Parser Text
    case s of
      "running"  -> AlgoRunning  <$> o .: "filledSize"
      "complete" -> AlgoComplete <$> o .: "totalFilled" <*> o .: "avgPrice"
      "stopped"  -> AlgoStopped  <$> o .: "reason"      <*> o .: "partialFill"
      _          -> fail "Invalid AlgoStatus"

-- ---------------------------------------------------------------------------
-- Engine / event types (no JSON needed for MarketEvent, TradeAction)
-- ---------------------------------------------------------------------------

data MarketEvent
  = OrderBookUpdate OrderBook
  | TradeUpdate     [Trade]
  | FillEvent       UserTrade
  | OrderUpdate     Order
  | TimerTick
  deriving stock (Eq, Show, Generic)

data TradeAction
  = PlaceOrder   OrderRequest
  | CancelOrder  CancelRequest
  | CancelAll    Coin
  | NoAction
  deriving stock (Eq, Show, Generic)

-- ---------------------------------------------------------------------------
-- LogLevel
-- ---------------------------------------------------------------------------

data LogLevel = Debug | Info | Warn | Error
  deriving stock (Eq, Ord, Show, Generic)

instance ToJSON LogLevel where
  toJSON = \case
    Debug -> String "debug"
    Info  -> String "info"
    Warn  -> String "warn"
    Error -> String "error"

instance FromJSON LogLevel where
  parseJSON = withText "LogLevel" $ \case
    "debug" -> pure Debug
    "info"  -> pure Info
    "warn"  -> pure Warn
    "error" -> pure Error
    _       -> fail "Invalid LogLevel"

-- ---------------------------------------------------------------------------
-- Network
-- ---------------------------------------------------------------------------

data Network = Mainnet | Testnet
  deriving stock (Eq, Ord, Show, Generic)

instance ToJSON Network where
  toJSON Mainnet = String "mainnet"
  toJSON Testnet = String "testnet"

instance FromJSON Network where
  parseJSON = withText "Network" $ \case
    "mainnet" -> pure Mainnet
    "testnet" -> pure Testnet
    _         -> fail "Expected mainnet or testnet"

-- ---------------------------------------------------------------------------
-- EngineConfig
-- ---------------------------------------------------------------------------

data EngineConfig = EngineConfig
  { ecEventQueueSize       :: Int
  , ecOrderPollIntervalMs  :: Int
  , ecHeartbeatIntervalMs  :: Int
  } deriving stock (Eq, Show, Generic)

instance ToJSON EngineConfig where
  toJSON c = object
    [ "eventQueueSize"      .= ecEventQueueSize c
    , "orderPollIntervalMs" .= ecOrderPollIntervalMs c
    , "heartbeatIntervalMs" .= ecHeartbeatIntervalMs c
    ]

instance FromJSON EngineConfig where
  parseJSON = withObject "EngineConfig" $ \o ->
    EngineConfig
      <$> o .: "eventQueueSize"
      <*> o .: "orderPollIntervalMs"
      <*> o .: "heartbeatIntervalMs"

-- ---------------------------------------------------------------------------
-- DailyStats
-- ---------------------------------------------------------------------------

data DailyStats = DailyStats
  { dsVolume     :: Scientific
  , dsTradeCount :: Int
  , dsFees       :: Scientific
  } deriving stock (Eq, Show, Generic)

instance ToJSON DailyStats where
  toJSON s = object
    [ "volume"     .= dsVolume s
    , "tradeCount" .= dsTradeCount s
    , "fees"       .= dsFees s
    ]

instance FromJSON DailyStats where
  parseJSON = withObject "DailyStats" $ \o ->
    DailyStats <$> o .: "volume" <*> o .: "tradeCount" <*> o .: "fees"
