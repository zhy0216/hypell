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
import Data.Text (Text)
import qualified Data.Text as T
import qualified Network.WebSockets as WS
import Wuss (runSecureClient)
import Hypell.Types (Coin(..), MarketEvent)

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
        Right (_v :: Value) -> do
          -- TODO: parse Hyperliquid WS message format into MarketEvent
          -- then: atomically $ writeTBQueue (wsEventBus client) event
          listenLoop conn
