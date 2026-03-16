module Hypell.Backtest.AccountSim
  ( runAccountBacktest
  , applyFill
  , simBalanceToToken
  ) where

import Data.Map.Strict qualified as Map
import Data.Scientific (Scientific)
import Effectful
import Effectful.Dispatch.Dynamic
import Effectful.State.Static.Local
import Hypell.Backtest.Types
import Hypell.Effect.Account
import Hypell.Types hiding (PlaceOrder, CancelOrder, CancelAll)

-- ---------------------------------------------------------------------------
-- Account interpreter for backtesting
-- ---------------------------------------------------------------------------

runAccountBacktest
  :: (State SimState :> es)
  => Eff (Account : es) a
  -> Eff es a
runAccountBacktest = interpret_ $ \case
  GetBalances -> do
    bals <- gets ssBalances
    pure $ map (uncurry simBalanceToToken) (Map.toList bals)
  GetUserTrades ->
    pure []

-- ---------------------------------------------------------------------------
-- Balance update on fill
-- ---------------------------------------------------------------------------

applyFill :: SimFill -> SimState -> SimState
applyFill fill st = st { ssBalances = updated }
  where
    coin     = sfCoin fill
    size     = sfSize fill
    price    = sfPrice fill
    fee      = sfFee fill
    bals     = ssBalances st
    notional = size * price

    updated = case sfSide fill of
      Buy ->
        let bals'  = deduct quoteCoin (notional + fee) bals
            bals'' = credit coin size bals'
        in  bals''
      Sell ->
        let bals'  = deduct coin size bals
            bals'' = credit quoteCoin (notional - fee) bals'
        in  bals''

    quoteCoin = Coin "USDC"

deduct :: Coin -> Scientific -> Map.Map Coin SimBalance -> Map.Map Coin SimBalance
deduct coin amount = Map.adjust (\b -> b { sbTotal     = sbTotal b - amount
                                         , sbAvailable = sbAvailable b - amount }) coin

credit :: Coin -> Scientific -> Map.Map Coin SimBalance -> Map.Map Coin SimBalance
credit coin amount = Map.insertWith addBalance coin (SimBalance amount amount)
  where
    addBalance new old = SimBalance
      { sbTotal     = sbTotal old + sbTotal new
      , sbAvailable = sbAvailable old + sbAvailable new
      }

-- ---------------------------------------------------------------------------
-- Conversion helper
-- ---------------------------------------------------------------------------

simBalanceToToken :: Coin -> SimBalance -> TokenBalance
simBalanceToToken coin sb = TokenBalance
  { tbCoin  = coin
  , tbTotal = sbTotal sb
  , tbHold  = sbTotal sb - sbAvailable sb
  }
