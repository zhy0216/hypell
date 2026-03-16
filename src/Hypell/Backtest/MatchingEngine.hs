module Hypell.Backtest.MatchingEngine
  ( matchAgainstTrades
  , matchAgainstBook
  ) where

import Data.Map.Strict qualified as Map
import Data.Scientific (Scientific)
import Data.Time (UTCTime)
import Hypell.Backtest.Types
import Hypell.Types

-- ---------------------------------------------------------------------------
-- Fill matching against trade ticks
-- ---------------------------------------------------------------------------

matchAgainstTrades
  :: UTCTime -> Scientific -> [Trade] -> SimState -> (SimState, [SimFill])
matchAgainstTrades now feeRate trades st =
  foldl (\acc t -> matchOneTrade now feeRate t acc) (st, []) trades

matchOneTrade
  :: UTCTime -> Scientific -> Trade
  -> (SimState, [SimFill]) -> (SimState, [SimFill])
matchOneTrade now feeRate trade (st, acc) =
  let px                     = trdPrice trade
      coin                   = trdCoin trade
      (remaining, newFills)  = Map.foldrWithKey (checkFill now feeRate coin px)
                                 (ssOpenOrders st, []) (ssOpenOrders st)
      st'                    = st { ssOpenOrders = remaining
                                  , ssFills      = ssFills st ++ newFills }
  in (st', acc ++ newFills)

checkFill
  :: UTCTime -> Scientific -> Coin -> Scientific
  -> OrderId -> (OrderRequest, Scientific)
  -> (Map.Map OrderId (OrderRequest, Scientific), [SimFill])
  -> (Map.Map OrderId (OrderRequest, Scientific), [SimFill])
checkFill now feeRate tradeCoin mktPx oid (req, limitPx) (remaining, fills)
  | orCoin req /= tradeCoin       = (remaining, fills)
  | shouldFill (orSide req) mktPx limitPx =
      let fee  = orSize req * limitPx * feeRate
          fill = SimFill oid (orCoin req) (orSide req) limitPx (orSize req) fee now
      in  (Map.delete oid remaining, fill : fills)
  | otherwise                     = (remaining, fills)

-- ---------------------------------------------------------------------------
-- Fill matching against order book snapshot
-- ---------------------------------------------------------------------------

matchAgainstBook
  :: UTCTime -> Scientific -> Coin -> OrderBook -> SimState -> (SimState, [SimFill])
matchAgainstBook now feeRate coin book st =
  let bestBid               = fmap fst $ listToMaybe (obBids book)
      bestAsk               = fmap fst $ listToMaybe (obAsks book)
      (remaining, newFills) = Map.foldrWithKey (checkBookFill now feeRate coin bestBid bestAsk)
                                (ssOpenOrders st, []) (ssOpenOrders st)
      st'                   = st { ssOpenOrders = remaining
                                 , ssFills      = ssFills st ++ newFills }
  in (st', newFills)

checkBookFill
  :: UTCTime -> Scientific -> Coin
  -> Maybe Scientific -> Maybe Scientific
  -> OrderId -> (OrderRequest, Scientific)
  -> (Map.Map OrderId (OrderRequest, Scientific), [SimFill])
  -> (Map.Map OrderId (OrderRequest, Scientific), [SimFill])
checkBookFill now feeRate bookCoin bestBid bestAsk oid (req, limitPx) (remaining, fills)
  | orCoin req /= bookCoin = (remaining, fills)
  | otherwise =
      let mktPx = case orSide req of { Buy -> bestAsk; Sell -> bestBid }
      in case mktPx of
           Nothing -> (remaining, fills)
           Just px ->
             if shouldFill (orSide req) px limitPx
               then let fee  = orSize req * limitPx * feeRate
                        fill = SimFill oid (orCoin req) (orSide req)
                                 limitPx (orSize req) fee now
                    in  (Map.delete oid remaining, fill : fills)
               else (remaining, fills)

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------

shouldFill :: Side -> Scientific -> Scientific -> Bool
shouldFill Buy  mktPx limitPx = mktPx <= limitPx
shouldFill Sell mktPx limitPx = mktPx >= limitPx

listToMaybe :: [a] -> Maybe a
listToMaybe []    = Nothing
listToMaybe (x:_) = Just x
