module Hypell.Interpreter.Exchange.IO
  ( runExchangeIO
  , encodeOrderAction
  , encodeCancelAction
  , coinToAssetIndex
  , parseOrderResponse
  ) where

import Control.Concurrent.STM
import Data.Aeson (Value, object, (.=), fromJSON, Result(..), withObject, (.:))
import Data.Aeson.Key (toText)
import Data.Aeson.KeyMap (toList)
import Data.Aeson.Types (parseMaybe, Parser)
import Data.Map.Strict qualified as Map
import Data.Text (Text, pack)
import Effectful
import Effectful.Dispatch.Dynamic
import Hypell.Api.Rest (RestClient, postExchange)
import Hypell.Effect.Exchange
import Hypell.Effect.Log (Log, log, logError)
import Hypell.Types hiding (PlaceOrder, CancelOrder, CancelAll, Error)
import Prelude hiding (log)

-- | IO interpreter for the Exchange effect.
-- Uses a RestClient for HTTP calls and a TVar for order tracking.
runExchangeIO
  :: (IOE :> es, Log :> es)
  => RestClient -> TVar (Map.Map OrderId Order)
  -> Eff (Exchange : es) a -> Eff es a
runExchangeIO rc ordersVar = interpret_ $ \case
  PlaceOrder req -> do
    log $ "Placing order: " <> tshow (orCoin req)
    let action = encodeOrderAction req
    result <- liftIO $ postExchange rc action
    case result of
      Left err -> do
        logError $ "PlaceOrder failed: " <> pack err
        pure $ OrderResponse "error" Nothing
      Right val ->
        pure $ parseOrderResponse val

  CancelOrder creq -> do
    log $ "Cancelling order: " <> tshow (crOrderId creq)
    let action = encodeCancelAction creq
    result <- liftIO $ postExchange rc action
    case result of
      Left err -> do
        logError $ "CancelOrder failed: " <> pack err
        pure $ CancelResponse "error"
      Right _val ->
        pure $ CancelResponse "success"

  CancelAll -> do
    orders <- liftIO $ atomically $ readTVar ordersVar
    log $ "Cancelling all orders (" <> tshow (Map.size orders) <> ")"
    let openOrders = Map.filter (\o -> orderStatus o `elem` [Open, Pending, PartiallyFilled]) orders
    mapM_ (\(oid, o) -> do
      let action = encodeCancelAction (CancelRequest (orderCoin o) oid)
      result <- liftIO $ postExchange rc action
      case result of
        Left err -> logError $ "Cancel " <> tshow oid <> " failed: " <> pack err
        Right _  -> pure ()
      ) (Map.toList openOrders)
    liftIO $ atomically $ modifyTVar' ordersVar
      (Map.filter (\o -> orderStatus o `notElem` [Open, Pending, PartiallyFilled]))

  GetOpenOrders -> do
    orders <- liftIO $ atomically $ readTVar ordersVar
    pure $ Map.elems $
      Map.filter (\o -> orderStatus o `elem` [Open, Pending, PartiallyFilled]) orders

-- | Encode an order request as a Hyperliquid order action JSON.
encodeOrderAction :: OrderRequest -> Value
encodeOrderAction req = object
  [ "type"     .= ("order" :: Text)
  , "orders"   .= [ object
      [ "a"        .= coinToAssetIndex (orCoin req)
      , "b"        .= (orSide req == Buy)
      , "p"        .= priceStr
      , "s"        .= orSize req
      , "r"        .= False
      , "t"        .= tifObj
      , "c"        .= orClientId req
      ] ]
  , "grouping" .= ("na" :: Text)
  ]
  where
    (priceStr, tifObj) = case orOrderType req of
      Market      -> ("0" :: Text, object ["limit" .= object ["tif" .= ("Ioc" :: Text)]])
      Limit p tif -> (tshow p, object ["limit" .= object ["tif" .= tif]])

-- | Encode a cancel request as a Hyperliquid cancel action JSON.
encodeCancelAction :: CancelRequest -> Value
encodeCancelAction creq = object
  [ "type"    .= ("cancel" :: Text)
  , "cancels" .= [ object
      [ "a"   .= coinToAssetIndex (crCoin creq)
      , "o"   .= crOrderId creq
      ] ]
  ]

-- | Map a coin to a Hyperliquid asset index.
-- Stub: returns 10000. Needs spot meta lookup for proper mapping.
coinToAssetIndex :: Coin -> Int
coinToAssetIndex _coin = 10000

-- | Parse a Hyperliquid order response.
-- Expected format:
--   {"status": "ok",  "response": {"type": "order", "data": {"statuses": [<status>]}}}
--   {"status": "err", "response": "<error message>"}
-- where <status> is one of:
--   {"resting": {"oid": 12345}}
--   {"filled":  {"totalSz": "1.0", "avgPx": "25.5", "oid": 12345}}
--   {"error": "message"}
parseOrderResponse :: Value -> OrderResponse
parseOrderResponse val = case parseMaybe parseHlOrderResp val of
  Just resp -> resp
  Nothing   -> OrderResponse "error" Nothing

parseHlOrderResp :: Value -> Parser OrderResponse
parseHlOrderResp = withObject "HlOrderResp" $ \o -> do
  status <- o .: "status" :: Parser Text
  case status of
    "err" -> do
      msg <- o .: "response" :: Parser Text
      pure $ OrderResponse msg Nothing
    _ -> do
      resp     <- o .: "response"
      dat      <- resp .: "data"
      statuses <- dat  .: "statuses" :: Parser [Value]
      case statuses of
        (s:_) -> parseHlStatus s
        []    -> pure $ OrderResponse "empty" Nothing

parseHlStatus :: Value -> Parser OrderResponse
parseHlStatus = withObject "HlStatus" $ \o ->
  case map (\(k, v) -> (toText k, v)) (toList o) of
    [("resting", v)] -> do
      oid <- withObject "resting" (.: "oid") v
      pure $ OrderResponse "resting" (Just oid)
    [("filled", v)] -> do
      oid <- withObject "filled" (.: "oid") v
      pure $ OrderResponse "filled" (Just oid)
    [("error", _)] ->
      pure $ OrderResponse "error" Nothing
    _ ->
      pure $ OrderResponse "unknown" Nothing

tshow :: Show a => a -> Text
tshow = pack . show
