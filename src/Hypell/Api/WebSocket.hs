module Hypell.Api.WebSocket
  ( WsClient(..)
  , connectWs
  , subscribe
  , wsListenerLoop
  ) where

import Control.Concurrent (threadDelay)
import Control.Concurrent.STM
import Control.Exception (SomeException, try)
import Data.Aeson (Value, Object, object, (.=), encode, eitherDecode, withObject, (.:))
import Data.Aeson.Types (parseMaybe, Parser)
import Data.Maybe (fromMaybe, listToMaybe, mapMaybe)
import Data.Scientific (Scientific)
import Data.Text (Text)
import qualified Data.Text as T
import Data.Time.Clock.POSIX (posixSecondsToUTCTime)
import qualified Network.WebSockets as WS
import Text.Read (readMaybe)
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
subscribe conn coin =
  WS.sendTextData conn $ encode $ object
    [ "method" .= ("subscribe" :: Text)
    , "subscription" .= object
        [ "type" .= ("trades" :: Text)
        , "coin" .= unCoin coin
        ]
    ]

-- Main WS loop with exponential backoff reconnect
wsListenerLoop :: WsClient -> IO ()
wsListenerLoop client = go 1
  where
    maxRetries :: Int
    maxRetries = 20

    maxDelay :: Int
    maxDelay = 30_000_000  -- 30 seconds

    go :: Int -> IO ()
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

    listenLoop :: WS.Connection -> IO ()
    listenLoop conn = do
      msg <- WS.receiveData conn
      case eitherDecode msg of
        Left _  -> listenLoop conn  -- skip unparseable
        Right v -> do
          case parseWsEvent v of
            Just event -> atomically $ writeTBQueue (wsEventBus client) event
            Nothing    -> pure ()  -- pong or unrecognised channel
          listenLoop conn

-- | Parse a Hyperliquid WebSocket message into a MarketEvent.
-- Handles: trades, l2Book, userFills channels.
parseWsEvent :: Value -> Maybe MarketEvent
parseWsEvent = parseMaybe $ withObject "WsMsg" $ \o -> do
  channel <- o .: "channel" :: Parser Text
  case channel of
    "trades"    -> parseTradesMsg o
    "l2Book"    -> parseL2BookMsg o
    "userFills" -> parseUserFillsMsg o
    _           -> fail "unrecognised channel"

parseTradesMsg :: Object -> Parser MarketEvent
parseTradesMsg o = do
  dataArr <- o .: "data" :: Parser [Value]
  trades  <- mapM parseTrade dataArr
  pure $ TradeUpdate trades

parseTrade :: Value -> Parser Trade
parseTrade = withObject "Trade" $ \o -> do
  coin    <- Coin <$> (o .: "coin" :: Parser Text)
  side    <- o .: "side"
  pxText  <- o .: "px"   :: Parser Text
  szText  <- o .: "sz"   :: Parser Text
  epochMs <- o .: "time" :: Parser Int
  px <- wsParseScientific pxText
  sz <- wsParseScientific szText
  let t = posixSecondsToUTCTime (fromIntegral epochMs / 1000)
  pure Trade { trdCoin = coin, trdSide = side, trdPrice = px, trdSize = sz, trdTime = t }

parseL2BookMsg :: Object -> Parser MarketEvent
parseL2BookMsg o = do
  dat     <- o .: "data"
  levels  <- dat .: "levels" :: Parser [[Value]]
  epochMs <- dat .: "time"   :: Parser Int
  let bids = fromMaybe [] $ parseLevels =<< listToMaybe levels
      asks = fromMaybe [] $ parseLevels =<< listToMaybe (drop 1 levels)
      t    = posixSecondsToUTCTime (fromIntegral epochMs / 1000)
  pure $ OrderBookUpdate (OrderBook bids asks t)

parseLevels :: [Value] -> Maybe [(Scientific, Scientific)]
parseLevels vs = Just $ mapMaybe (parseMaybe parseLevelEntry) vs

parseLevelEntry :: Value -> Parser (Scientific, Scientific)
parseLevelEntry = withObject "Level" $ \o -> do
  pxText <- o .: "px" :: Parser Text
  szText <- o .: "sz" :: Parser Text
  px <- wsParseScientific pxText
  sz <- wsParseScientific szText
  pure (px, sz)

parseUserFillsMsg :: Object -> Parser MarketEvent
parseUserFillsMsg o = do
  dat   <- o .: "data"
  fills <- dat .: "fills" :: Parser [Value]
  case fills of
    (f:_) -> FillEvent <$> parseFillEntry f
    []    -> fail "empty fills"

parseFillEntry :: Value -> Parser UserTrade
parseFillEntry = withObject "Fill" $ \o -> do
  coin    <- Coin <$> (o .: "coin" :: Parser Text)
  side    <- o .: "side"
  pxText  <- o .: "px"   :: Parser Text
  szText  <- o .: "sz"   :: Parser Text
  feeText <- o .: "fee"  :: Parser Text
  epochMs <- o .: "time" :: Parser Int
  oid     <- o .: "oid"
  px  <- wsParseScientific pxText
  sz  <- wsParseScientific szText
  fee <- wsParseScientific feeText
  let t = posixSecondsToUTCTime (fromIntegral epochMs / 1000)
  pure UserTrade { utCoin = coin, utSide = side, utPrice = px, utSize = sz
                 , utFee = fee, utTime = t, utOrderId = oid }

wsParseScientific :: Text -> Parser Scientific
wsParseScientific t = case readMaybe (T.unpack t) of
  Just n  -> pure n
  Nothing -> fail $ "Invalid number: " <> T.unpack t
