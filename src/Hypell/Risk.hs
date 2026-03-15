module Hypell.Risk
  ( evaluateRisk
  ) where

import Data.Map.Strict qualified as Map
import Data.Text (Text)
import qualified Data.Text as T
import Hypell.Types

-- | Pure risk evaluation function.
-- Checks order against limits and current state.
-- Returns 'RiskAllow' if the order passes all checks,
-- or 'RiskReject' with a reason if it fails.
evaluateRisk
  :: RiskLimits
  -> DailyStats
  -> Map.Map Coin TokenBalance
  -> OrderRequest
  -> RiskResult
evaluateRisk limits stats positions req
  | orSize req > rlMaxOrderSize limits
    = RiskReject $ "Order size " <> tshow (orSize req)
        <> " exceeds max " <> tshow (rlMaxOrderSize limits)
  | exceedsPositionLimit
    = RiskReject $ "Would exceed position limit for " <> tshow (orCoin req)
  | dsVolume stats + orderNotional > rlMaxDailyVolume limits
    = RiskReject "Daily volume limit exceeded"
  | otherwise
    = RiskAllow
  where
    exceedsPositionLimit = case Map.lookup (orCoin req) (rlMaxPositionSize limits) of
      Nothing    -> False
      Just maxSz -> currentPos + orSize req > maxSz
    currentPos = maybe 0 tbTotal $ Map.lookup (orCoin req) positions
    orderNotional = orSize req  -- for spot, notional ~ size (simplified)

tshow :: Show a => a -> Text
tshow = T.pack . show
