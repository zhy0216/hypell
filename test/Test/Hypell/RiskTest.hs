module Test.Hypell.RiskTest (tests) where

import Test.Tasty
import Test.Tasty.HUnit
import Test.Tasty.QuickCheck
import Data.Map.Strict qualified as Map
import Data.Scientific (Scientific, scientific)
import Hypell.Types
import Hypell.Risk

defaultLimits :: RiskLimits
defaultLimits = RiskLimits
  { rlMaxOrderSize    = scientific 1000 0
  , rlMaxDailyVolume  = scientific 50000 0
  , rlCooldownMs      = 500
  , rlMaxPositionSize = Map.singleton (Coin "HYPE/USDC") (scientific 5000 0)
  }

emptyStats :: DailyStats
emptyStats = DailyStats
  { dsVolume     = 0
  , dsTradeCount = 0
  , dsFees       = 0
  }

mkOrder :: Coin -> Side -> Scientific -> OrderRequest
mkOrder coin side sz = OrderRequest
  { orCoin      = coin
  , orSide      = side
  , orSize      = sz
  , orOrderType = Market
  , orClientId  = Nothing
  }

tests :: TestTree
tests = testGroup "Hypell.Risk"
  [ testCase "passes valid order" $
      evaluateRisk defaultLimits emptyStats mempty (mkOrder (Coin "HYPE/USDC") Buy 100)
        @?= RiskAllow

  , testCase "rejects order exceeding max size" $
      case evaluateRisk defaultLimits emptyStats mempty (mkOrder (Coin "HYPE/USDC") Buy 1500) of
        RiskReject _ -> pure ()
        RiskAllow    -> assertFailure "expected rejection"

  , testCase "rejects order exceeding position limit" $ do
      let positions = Map.singleton (Coin "HYPE/USDC")
            (TokenBalance (Coin "HYPE/USDC") 4500 0)
      case evaluateRisk defaultLimits emptyStats positions (mkOrder (Coin "HYPE/USDC") Buy 600) of
        RiskReject _ -> pure ()
        RiskAllow    -> assertFailure "expected rejection"

  , testCase "rejects order exceeding daily volume" $ do
      let stats = emptyStats { dsVolume = scientific 49500 0 }
      case evaluateRisk defaultLimits stats mempty (mkOrder (Coin "HYPE/USDC") Buy 600) of
        RiskReject _ -> pure ()
        RiskAllow    -> assertFailure "expected rejection"

  , testCase "passes order within all limits" $
      evaluateRisk defaultLimits emptyStats mempty (mkOrder (Coin "OTHER") Buy 500)
        @?= RiskAllow

  , testCase "passes order at exact max size" $
      evaluateRisk defaultLimits emptyStats mempty (mkOrder (Coin "HYPE/USDC") Buy 1000)
        @?= RiskAllow

  , testCase "rejects when position + order exceeds limit" $ do
      let positions = Map.singleton (Coin "HYPE/USDC")
            (TokenBalance (Coin "HYPE/USDC") 4500 0)
      case evaluateRisk defaultLimits emptyStats positions (mkOrder (Coin "HYPE/USDC") Buy 501) of
        RiskReject _ -> pure ()
        RiskAllow    -> assertFailure "expected rejection"

  , testProperty "any order above maxOrderSize is rejected" $ \(Positive sz) ->
      let bigSz = scientific (1000 + sz) 0
          result = evaluateRisk defaultLimits emptyStats mempty
                     (mkOrder (Coin "X") Buy bigSz)
      in result /= RiskAllow
  ]
