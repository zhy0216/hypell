module Hypell.Backtest.Runner
  ( runBacktest
  ) where

import Colog.Core (LogAction(..))
import Data.List (foldl')
import Data.Map.Strict qualified as Map
import Data.Scientific (Scientific)
import Data.Time (UTCTime)
import Effectful
import Effectful.State.Static.Local

import Hypell.Backtest.AccountSim (applyFill, simBalanceToToken)
import Hypell.Backtest.MatchingEngine (matchAgainstTrades, matchAgainstBook)
import Hypell.Backtest.Metrics (computeMetrics)
import Hypell.Backtest.Types
import Hypell.Effect.Log (runLog)
import Hypell.Interpreter.Account.Pure (runAccountPure)
import Hypell.Interpreter.MarketData.Pure
  (runMarketDataPure, MockMarketDataState(..), emptyMockMarketData)
import Hypell.Strategy (Strategy(..))
import Hypell.Types hiding (PlaceOrder, CancelOrder, CancelAll)
import qualified Hypell.Types as T

-- ---------------------------------------------------------------------------
-- Top-level backtest runner
-- ---------------------------------------------------------------------------

runBacktest
  :: Strategy s
  => BacktestConfig
  -> s
  -> [MarketEvent]
  -> IO BacktestResult
runBacktest cfg strategy events = do
  let simSt0 = initialSimState cfg
      mdSt0  = emptyMockMarketData

  s0 <- callInitStrategy simSt0 mdSt0 strategy

  (finalSimSt, _) <- processAll cfg simSt0 mdSt0 s0 events

  let fills   = ssFills finalSimSt
      metrics = computeMetrics fills
  pure BacktestResult
    { brFills      = fills
    , brFinalState = finalSimSt
    , brMetrics    = metrics
    }

-- ---------------------------------------------------------------------------
-- Event processing loop
-- ---------------------------------------------------------------------------

processAll
  :: Strategy s
  => BacktestConfig
  -> SimState
  -> MockMarketDataState
  -> s
  -> [MarketEvent]
  -> IO (SimState, s)
processAll _   simSt _    s []         = pure (simSt, s)
processAll cfg simSt mdSt s (ev:rest) = do
  let now = eventTime ev

  -- 1. Match resting orders against incoming market data
  let (simSt', newFills) = case ev of
        TradeUpdate ts     -> matchAgainstTrades now (bcFeeRate cfg) ts simSt
        OrderBookUpdate coin ob -> matchAgainstBook now (bcFeeRate cfg) coin ob simSt
        _                  -> (simSt, [])

  -- 2. Apply fills to simulated balances
  let simSt'' = foldl' (flip applyFill) simSt' newFills

  -- 3. Update mock MarketData state (so strategy sees fresh order books)
  let mdSt' = updateMDState ev mdSt

  -- 4. Inject FillEvents from matching, then the original event
  let evts = map mkFillEvent newFills ++ [ev]

  -- 5. Run strategy through each event, processing resulting actions
  (simSt''', s') <- foldlM (runOneEvent cfg mdSt') (simSt'', s) evts

  processAll cfg simSt''' mdSt' s' rest

-- ---------------------------------------------------------------------------
-- Single event: call onEvent, execute actions
-- ---------------------------------------------------------------------------

runOneEvent
  :: Strategy s
  => BacktestConfig
  -> MockMarketDataState
  -> (SimState, s)
  -> MarketEvent
  -> IO (SimState, s)
runOneEvent cfg mdSt (simSt, s) ev = do
  (s', actions) <- callOnEvent simSt mdSt s ev
  let simSt' = foldl' (executeAction cfg (eventTrades ev) (eventTime ev)) simSt actions
  pure (simSt', s')

-- ---------------------------------------------------------------------------
-- Execute a TradeAction against SimState (pure)
-- ---------------------------------------------------------------------------

executeAction
  :: BacktestConfig
  -> [Trade]
  -> UTCTime
  -> SimState
  -> TradeAction
  -> SimState
executeAction cfg trades now simSt = \case
  T.PlaceOrder req ->
    let risk = checkRisk (bcRiskLimits cfg) (ssDailyStats simSt) req
    in case risk of
         RiskReject _ -> simSt
         RiskAllow    -> placeOrderSim cfg trades now req simSt
  T.CancelOrder cr  ->
    simSt { ssOpenOrders = Map.delete (crOrderId cr) (ssOpenOrders simSt) }
  T.CancelAll _     ->
    simSt { ssOpenOrders = Map.empty }
  T.NoAction        -> simSt

placeOrderSim
  :: BacktestConfig
  -> [Trade]
  -> UTCTime
  -> OrderRequest
  -> SimState
  -> SimState
placeOrderSim cfg trades now req st =
  let oid = ssNextOrderId st
      st' = st { ssNextOrderId = oid + 1 }
  in case orOrderType req of
       Market ->
         let bestPx = marketBest (orSide req) trades
         in case bestPx of
              Nothing -> st'
              Just px ->
                let fillPx = applySlip (bcSlippage cfg) (orSide req) px
                    fee    = orSize req * fillPx * bcFeeRate cfg
                    fill   = SimFill oid (orCoin req) (orSide req) fillPx (orSize req) fee now
                in applyFill fill st' { ssFills = ssFills st' ++ [fill] }
       Limit px _ ->
         st' { ssOpenOrders = Map.insert oid (req, px) (ssOpenOrders st') }

-- ---------------------------------------------------------------------------
-- Call Strategy.initStrategy or onEvent in the pure effect stack
-- ---------------------------------------------------------------------------

callInitStrategy
  :: Strategy s
  => SimState -> MockMarketDataState -> s -> IO s
callInitStrategy simSt mdSt s = runEff $ do
  let bals = simStateToBalances simSt
  runLog silentLogAction
    . evalState mdSt
    . runMarketDataPure
    . evalState bals
    . runAccountPure
    $ initStrategy s

callOnEvent
  :: Strategy s
  => SimState
  -> MockMarketDataState
  -> s
  -> MarketEvent
  -> IO (s, [TradeAction])
callOnEvent simSt mdSt s ev = runEff $ do
  let bals = simStateToBalances simSt
  runLog silentLogAction
    . evalState mdSt
    . runMarketDataPure
    . evalState bals
    . runAccountPure
    $ onEvent s ev

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------

silentLogAction :: LogAction IO msg
silentLogAction = LogAction $ \_ -> pure ()

simStateToBalances :: SimState -> [TokenBalance]
simStateToBalances = map (uncurry simBalanceToToken) . Map.toList . ssBalances

checkRisk :: RiskLimits -> DailyStats -> OrderRequest -> RiskResult
checkRisk limits stats req
  | orSize req > rlMaxOrderSize limits = RiskReject "order size limit"
  | dsVolume stats + orSize req > rlMaxDailyVolume limits = RiskReject "daily volume limit"
  | otherwise = RiskAllow

marketBest :: Side -> [Trade] -> Maybe Scientific
marketBest _    []  = Nothing
marketBest Buy  ts  = Just $ minimum (map trdPrice ts)
marketBest Sell ts  = Just $ maximum (map trdPrice ts)

applySlip :: SlippageModel -> Side -> Scientific -> Scientific
applySlip NoSlippage      _    px = px
applySlip (FixedBps bps) Buy  px  = px * (1 + bps / 10000)
applySlip (FixedBps bps) Sell px  = px * (1 - bps / 10000)

eventTime :: MarketEvent -> UTCTime
eventTime (OrderBookUpdate _ ob) = obTime ob
eventTime (TradeUpdate (t:_))  = trdTime t
eventTime (TradeUpdate [])     = error "eventTime: empty TradeUpdate"
eventTime (FillEvent ut)       = utTime ut
eventTime (OrderUpdate o)      = orderTime o
eventTime TimerTick            = error "TimerTick has no timestamp; filter before runBacktest"

eventTrades :: MarketEvent -> [Trade]
eventTrades (TradeUpdate ts) = ts
eventTrades _                = []

mkFillEvent :: SimFill -> MarketEvent
mkFillEvent sf = FillEvent UserTrade
  { utCoin    = sfCoin sf
  , utSide    = sfSide sf
  , utPrice   = sfPrice sf
  , utSize    = sfSize sf
  , utFee     = sfFee sf
  , utTime    = sfTime sf
  , utOrderId = sfOrderId sf
  }

updateMDState :: MarketEvent -> MockMarketDataState -> MockMarketDataState
updateMDState (OrderBookUpdate coin ob) mmd =
  mmd { mmdOrderBooks = upsert coin ob (mmdOrderBooks mmd) }
  where
    upsert c newOb []              = [(c, newOb)]
    upsert c newOb ((c', _):rest)
      | c == c'                    = (c, newOb) : rest
    upsert c newOb (x:rest)        = x : upsert c newOb rest
updateMDState _ mmd = mmd

foldlM :: Monad m => (b -> a -> m b) -> b -> [a] -> m b
foldlM _ z []     = pure z
foldlM f z (x:xs) = f z x >>= \z' -> foldlM f z' xs

