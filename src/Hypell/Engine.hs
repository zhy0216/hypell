module Hypell.Engine
  ( EngineEnv(..)
  , initEnv
  , runEngine
  , eventLoop
  , executeAction
  ) where

import Control.Concurrent (threadDelay)
import Control.Concurrent.Async (withAsync)
import Control.Concurrent.STM
import Control.Monad (forM_, forever)
import Data.Map.Strict qualified as Map
import Data.Text (Text, pack)
import Effectful
import Prelude hiding (log)

import Hypell.Api.Rest (RestClient, newRestClient)
import Hypell.Api.WebSocket (WsClient, connectWs, wsListenerLoop)
import Hypell.Config (Config(..))
import Hypell.Effect.Account (Account)
import Hypell.Effect.Exchange (Exchange)
import Hypell.Effect.Log (Log, log, logError, runLog, mkLogAction)
import Hypell.Effect.MarketData (MarketData)
import Hypell.Effect.OrderManager (OrderManager)
import Hypell.Effect.RiskControl (RiskControl, checkOrder)
import Hypell.Interpreter.Account.IO (runAccountIO)
import Hypell.Interpreter.Exchange.IO (runExchangeIO)
import Hypell.Interpreter.MarketData.IO (runMarketDataIO)
import Hypell.Interpreter.OrderManager (runOrderManagerIO)
import Hypell.Interpreter.RiskControl (runRiskControlIO)
import Hypell.Strategy (Strategy(..))
import Hypell.Types hiding (PlaceOrder, CancelOrder, CancelAll)
import qualified Hypell.Types as T
import qualified Hypell.Effect.Exchange as Exch
import qualified Hypell.Effect.OrderManager as OM

-- | Runtime environment for the engine, holding all shared mutable state.
data EngineEnv = EngineEnv
  { eeConfig     :: Config
  , eeEventBus   :: TBQueue MarketEvent
  , eeRestClient :: RestClient
  , eeWsClient   :: WsClient
  , eeRiskLimits :: TVar RiskLimits
  , eePositions  :: TVar (Map.Map Coin TokenBalance)
  , eeOpenOrders :: TVar (Map.Map OrderId Order)
  , eeDailyStats :: TVar DailyStats
  }

-- | Initialize the engine environment from config.
-- Creates all TVars, RestClient, and WsClient.
initEnv :: Config -> IO EngineEnv
initEnv cfg = do
  eventBus   <- newTBQueueIO (fromIntegral $ ecEventQueueSize (cfgEngine cfg))
  rc         <- newRestClient (cfgApiUrl cfg) (cfgPrivateKey cfg)
  ws         <- connectWs (cfgWsUrl cfg) eventBus
  limitsVar  <- newTVarIO (cfgRisk cfg)
  posVar     <- newTVarIO Map.empty
  ordersVar  <- newTVarIO Map.empty
  statsVar   <- newTVarIO (DailyStats 0 0 0)
  pure EngineEnv
    { eeConfig     = cfg
    , eeEventBus   = eventBus
    , eeRestClient = rc
    , eeWsClient   = ws
    , eeRiskLimits = limitsVar
    , eePositions  = posVar
    , eeOpenOrders = ordersVar
    , eeDailyStats = statsVar
    }

-- | Emit a TimerTick event on the bus at the given interval.
timerLoop :: TBQueue MarketEvent -> Int -> IO ()
timerLoop bus intervalMs = forever $ do
  threadDelay (intervalMs * 1000)
  atomically $ writeTBQueue bus TimerTick

-- | Main event loop: reads events from the bus, passes them to the strategy,
-- and executes resulting actions.
eventLoop
  :: ( RiskControl :> es, Exchange :> es, OrderManager :> es
     , MarketData :> es, Account :> es, Log :> es, IOE :> es)
  => TBQueue MarketEvent -> s -> (s -> MarketEvent -> Eff es (s, [TradeAction])) -> Eff es ()
eventLoop eventBus initialState onEvt = go initialState
  where
    go st = do
      event <- liftIO $ atomically $ readTBQueue eventBus
      (st', actions) <- onEvt st event
      forM_ actions executeAction
      go st'

-- | Execute a single TradeAction: risk-check orders before submitting,
-- or forward cancels directly.
executeAction
  :: (RiskControl :> es, Exchange :> es, OrderManager :> es, Log :> es, IOE :> es)
  => TradeAction -> Eff es ()
executeAction = \case
  T.PlaceOrder req -> do
    riskResult <- checkOrder req
    case riskResult of
      RiskAllow -> do
        log $ "Risk passed, submitting order for " <> tshow (orCoin req)
        _mo <- OM.submitOrder req
        pure ()
      RiskReject reason -> do
        logError $ "Risk rejected order: " <> reason
  T.CancelOrder creq -> do
    log $ "Cancelling order " <> tshow (crOrderId creq)
    _resp <- Exch.cancelOrder creq
    pure ()
  T.CancelAll _coin -> do
    log $ "Cancelling all orders"
    Exch.cancelAll
  T.NoAction -> pure ()

-- | Top-level engine runner. Wires all IO interpreters and runs the event loop
-- with concurrent WS listener and timer threads.
runEngine :: Strategy s => Config -> s -> IO ()
runEngine cfg initialStrategy = do
  env <- initEnv cfg
  let logAction  = mkLogAction (cfgLogLevel cfg)
      intervalMs = ecHeartbeatIntervalMs (cfgEngine cfg)
  withAsync (wsListenerLoop (eeWsClient env)) $ \_ ->
    withAsync (timerLoop (eeEventBus env) intervalMs) $ \_ ->
      runEff
        . runLog logAction
        . runRiskControlIO (eeRiskLimits env) (eeDailyStats env) (eePositions env)
        . runExchangeIO (eeRestClient env) (eeOpenOrders env)
        . runOrderManagerIO (eeOpenOrders env)
        . runMarketDataIO (eeRestClient env) (eeWsClient env)
        . runAccountIO (eeRestClient env) (cfgWalletAddress cfg)
        $ do
            log "Engine starting..."
            strategy' <- initStrategy initialStrategy
            eventLoop (eeEventBus env) strategy' onEvent

tshow :: Show a => a -> Text
tshow = pack . show
