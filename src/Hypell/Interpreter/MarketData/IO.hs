module Hypell.Interpreter.MarketData.IO
  ( runMarketDataIO
  ) where

import Control.Concurrent.STM
import Data.Aeson (object, (.=), fromJSON, Result(..))
import Data.Text (Text, pack)
import Effectful
import Effectful.Dispatch.Dynamic
import Hypell.Api.Rest (RestClient, postInfo)
import Hypell.Api.WebSocket (WsClient(..), subscribe)
import Hypell.Effect.Log (Log, log, logError)
import Hypell.Effect.MarketData
import Hypell.Types hiding (Error)
import Prelude hiding (log)
import qualified Network.WebSockets as WS

-- | IO interpreter for the MarketData effect.
-- Uses RestClient for HTTP info queries and WsClient for subscriptions.
runMarketDataIO
  :: (IOE :> es, Log :> es)
  => RestClient -> WsClient
  -> Eff (MarketData : es) a -> Eff es a
runMarketDataIO rc ws = interpret_ $ \case
  GetSpotMeta -> do
    log "Fetching spot meta"
    let payload = object ["type" .= ("spotMeta" :: Text)]
    result <- liftIO $ postInfo rc payload
    case result of
      Left err -> do
        logError $ "GetSpotMeta failed: " <> pack err
        pure $ SpotMeta [] []
      Right val -> case fromJSON val of
        Success meta -> pure meta
        Error err -> do
          logError $ "GetSpotMeta parse error: " <> pack err
          pure $ SpotMeta [] []

  GetSpotAssetCtxs -> do
    log "Fetching spot asset contexts"
    let payload = object ["type" .= ("spotMetaAndAssetCtxs" :: Text)]
    result <- liftIO $ postInfo rc payload
    case result of
      Left err -> do
        logError $ "GetSpotAssetCtxs failed: " <> pack err
        pure []
      Right val -> case fromJSON val of
        Success ctxs -> pure ctxs
        Error err -> do
          logError $ "GetSpotAssetCtxs parse error: " <> pack err
          pure []

  GetOrderBook coin -> do
    log $ "Fetching order book for " <> unCoin coin
    let payload = object
          [ "type" .= ("l2Book" :: Text)
          , "coin" .= unCoin coin
          ]
    result <- liftIO $ postInfo rc payload
    case result of
      Left err -> do
        logError $ "GetOrderBook failed: " <> pack err
        pure $ OrderBook [] [] (read "2026-01-01 00:00:00 UTC")
      Right val -> case fromJSON val of
        Success ob -> pure ob
        Error err -> do
          logError $ "GetOrderBook parse error: " <> pack err
          pure $ OrderBook [] [] (read "2026-01-01 00:00:00 UTC")

  SubscribeTrades coin -> do
    log $ "Subscribing to trades for " <> unCoin coin
    mConn <- liftIO $ atomically $ readTVar (wsConn ws)
    case mConn of
      Nothing -> logError "SubscribeTrades: WebSocket not connected"
      Just (conn :: WS.Connection) -> liftIO $ subscribe conn coin
