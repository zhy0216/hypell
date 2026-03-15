module Test.Hypell.StrategyTest (tests) where

import Test.Tasty
import Test.Tasty.HUnit
import Data.Scientific (scientific)
import Effectful
import Effectful.State.Static.Local
import Hypell.Types
import Hypell.Strategy
import Hypell.Effect.Log (runLog)
import Hypell.Interpreter.MarketData.Pure
import Hypell.Interpreter.Account.Pure
import Colog.Core (LogAction(..))
import Data.Text (Text)

-- A trivial test strategy: buy on every trade event
data BuyOnTrade = BuyOnTrade
  deriving stock (Eq, Show)

instance Strategy BuyOnTrade where
  strategyName _ = "buy-on-trade"
  initStrategy s = pure s
  onEvent s (TradeUpdate trades) = pure
    ( s
    , [ PlaceOrder OrderRequest
          { orCoin      = trdCoin t
          , orSide      = Buy
          , orSize      = scientific 10 0
          , orOrderType = Market
          , orClientId  = Nothing
          }
      | t <- trades
      ]
    )
  onEvent s _ = pure (s, [])
  onShutdown _ = pure ()

tests :: TestTree
tests = testGroup "Hypell.Strategy"
  [ testCase "BuyOnTrade emits PlaceOrder on trade event" $ do
      let trade = Trade
            { trdCoin  = Coin "HYPE/USDC"
            , trdSide  = Buy
            , trdPrice = scientific 25 0
            , trdSize  = scientific 100 0
            , trdTime  = read "2026-03-16 12:00:00 UTC"
            }
      (_, actions) <- runEff
        . runLog (LogAction $ \(_ :: Text) -> pure ())
        . evalState ([] :: [TokenBalance])
        . runAccountPure
        . evalState emptyMockMarketData
        . runMarketDataPure
        $ onEvent BuyOnTrade (TradeUpdate [trade])
      length actions @?= 1
      case head actions of
        PlaceOrder req -> do
          orCoin req @?= Coin "HYPE/USDC"
          orSide req @?= Buy
          orSize req @?= scientific 10 0
        _ -> assertFailure "expected PlaceOrder"

  , testCase "BuyOnTrade emits no actions on timer tick" $ do
      (_, actions) <- runEff
        . runLog (LogAction $ \(_ :: Text) -> pure ())
        . evalState ([] :: [TokenBalance])
        . runAccountPure
        . evalState emptyMockMarketData
        . runMarketDataPure
        $ onEvent BuyOnTrade TimerTick
      length actions @?= 0

  , testCase "BuyOnTrade emits multiple actions for multiple trades" $ do
      let mkTrade c = Trade
            { trdCoin  = Coin c
            , trdSide  = Sell
            , trdPrice = scientific 10 0
            , trdSize  = scientific 50 0
            , trdTime  = read "2026-03-16 12:00:00 UTC"
            }
      (_, actions) <- runEff
        . runLog (LogAction $ \(_ :: Text) -> pure ())
        . evalState ([] :: [TokenBalance])
        . runAccountPure
        . evalState emptyMockMarketData
        . runMarketDataPure
        $ onEvent BuyOnTrade (TradeUpdate [mkTrade "A", mkTrade "B", mkTrade "C"])
      length actions @?= 3
  ]
