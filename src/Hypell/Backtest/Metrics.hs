module Hypell.Backtest.Metrics
  ( computeMetrics
  , pnlCurve
  ) where

import Data.List (foldl', sortOn)
import Data.Map.Strict qualified as Map
import Data.Scientific (Scientific, toRealFloat, fromFloatDigits)
import Data.Text (Text)
import Data.Text qualified as T
import Data.Time (UTCTime)
import Hypell.Backtest.Types
import Hypell.Types

-- ---------------------------------------------------------------------------
-- Public API
-- ---------------------------------------------------------------------------

computeMetrics :: [SimFill] -> BacktestMetrics
computeMetrics fills =
  let curve     = pnlCurve fills
      perTrade  = perTradePnl fills
      totalPnl  = if null curve then 0 else snd (last curve)
      totalFees = sum (map sfFee fills)
      tradeCount = length fills
      wins      = length [ p | (_, p) <- perTrade, p > 0 ]
      winRate   = if tradeCount == 0 then 0
                  else fromIntegral wins / fromIntegral tradeCount
      maxDD     = maxDrawdown (map snd curve)
      sharpe    = sharpeRatio (map snd curve)
  in BacktestMetrics
       { bmTotalPnl    = totalPnl
       , bmTotalFees   = totalFees
       , bmTradeCount  = tradeCount
       , bmWinRate     = winRate
       , bmMaxDrawdown = maxDD
       , bmSharpeRatio = sharpe
       , bmPnlCurve    = curve
       , bmPerTradePnl = perTrade
       }

-- ---------------------------------------------------------------------------
-- PnL curve (cumulative realised PnL over time)
-- ---------------------------------------------------------------------------

pnlCurve :: [SimFill] -> [(UTCTime, Scientific)]
pnlCurve fills =
  let sorted          = sortOn sfTime fills
      (_, _, pts)     = foldl' step (Map.empty, 0, []) sorted
  in pts
  where
    step (inv, cumPnl, acc) fill = case sfSide fill of
      Buy ->
        let coin = sfCoin fill
            cost = sfSize fill * sfPrice fill + sfFee fill
            inv' = Map.insertWith addPos coin (sfSize fill, cost) inv
        in (inv', cumPnl, acc ++ [(sfTime fill, cumPnl)])
      Sell ->
        let (pnl, inv') = realiseSell (sfCoin fill) (sfSize fill) (sfPrice fill) (sfFee fill) inv
            cumPnl'     = cumPnl + pnl
        in (inv', cumPnl', acc ++ [(sfTime fill, cumPnl')])

    addPos (q1, c1) (q2, c2) = (q1 + q2, c1 + c2)

realiseSell
  :: Coin
  -> Scientific
  -> Scientific
  -> Scientific
  -> Map.Map Coin (Scientific, Scientific)
  -> (Scientific, Map.Map Coin (Scientific, Scientific))
realiseSell coin qty px fee inv =
  case Map.lookup coin inv of
    Nothing       -> (px * qty - fee, inv)
    Just (heldQ, costBasis) ->
      let fillQ     = min qty heldQ
          costPerU  = if heldQ == 0 then 0 else costBasis / heldQ
          realised  = fillQ * px - fillQ * costPerU - fee
          remaining = heldQ - fillQ
          inv'      = if remaining <= 0
                        then Map.delete coin inv
                        else Map.insert coin (remaining, remaining * costPerU) inv
      in (realised, inv')

-- ---------------------------------------------------------------------------
-- Per-trade PnL using simple FIFO matching of buy→sell pairs
-- ---------------------------------------------------------------------------

perTradePnl :: [SimFill] -> [(Text, Scientific)]
perTradePnl fills =
  let sorted = sortOn sfTime fills
      (_, results) = foldl' matchFill (Map.empty, []) sorted
  in results
  where
    matchFill (buyQ, acc) fill =
      case sfSide fill of
        Buy ->
          let q    = sfSize fill
              cost = sfSize fill * sfPrice fill + sfFee fill
              coin = sfCoin fill
              buyQ' = Map.insertWith (\(a,b) (c,d) -> (a+c, b+d))
                        coin (q, cost) buyQ
          in (buyQ', acc)
        Sell ->
          let coin = sfCoin fill
              qty  = sfSize fill
              px   = sfPrice fill
              fee  = sfFee fill
          in case Map.lookup coin buyQ of
               Nothing -> (buyQ, acc)
               Just (heldQ, costBasis) ->
                 let fillQ    = min qty heldQ
                     costPerU = if heldQ == 0 then 0 else costBasis / heldQ
                     pnl      = fillQ * px - fillQ * costPerU - fee
                     remaining = heldQ - fillQ
                     buyQ'    = if remaining <= 0
                                  then Map.delete coin buyQ
                                  else Map.insert coin (remaining, remaining * costPerU) buyQ
                     label    = T.pack (show (sfOrderId fill))
                 in  (buyQ', acc ++ [(label, pnl)])

-- ---------------------------------------------------------------------------
-- Max drawdown from a PnL curve
-- ---------------------------------------------------------------------------

maxDrawdown :: [Scientific] -> Scientific
maxDrawdown [] = 0
maxDrawdown xs =
  let (_, dd) = foldl' step (head xs, 0) xs
  in dd
  where
    step (peak, maxDD) v =
      let peak'  = max peak v
          dd     = peak' - v
          maxDD' = max maxDD dd
      in (peak', maxDD')

-- ---------------------------------------------------------------------------
-- Annualised Sharpe ratio (assumes fills are spread over multiple days)
-- ---------------------------------------------------------------------------

sharpeRatio :: [Scientific] -> Scientific
sharpeRatio [] = 0
sharpeRatio [_] = 0
sharpeRatio xs =
  let diffs = zipWith (-) (tail xs) xs
      n     = fromIntegral (length diffs) :: Double
      mean  = toRealFloat (sum diffs) / n
      var   = sum [ (toRealFloat d - mean) ^ (2 :: Int) | d <- diffs ] / n
      std   = sqrt var
  in if std == 0 then 0
     else fromFloatDigits (mean / std * sqrt 252)
