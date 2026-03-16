{-# LANGUAGE StrictData #-}

module Hypell.Config
  ( Config(..)
  , ConfigFile(..)
  , LoggingConfig(..)
  , loadConfig
  , defaultEngineConfig
  ) where

import Data.Aeson (FromJSON(..), withObject, (.:), (.:?), (.!=))
import Data.ByteString (ByteString)
import qualified Data.Text as T
import qualified Data.Text.Encoding as TE
import qualified Data.Yaml as Yaml
import GHC.Generics (Generic)
import System.Environment (lookupEnv)

import Hypell.Types (EngineConfig(..), LogLevel(..), Network(..), RiskLimits(..))

-- ---------------------------------------------------------------------------
-- Config types
-- ---------------------------------------------------------------------------

-- | Runtime configuration, fully resolved (includes private key from env).
data Config = Config
  { cfgNetwork       :: Network
  , cfgApiUrl        :: T.Text
  , cfgWsUrl         :: T.Text
  , cfgPrivateKey    :: ByteString
  , cfgWalletAddress :: T.Text
  , cfgRisk          :: RiskLimits
  , cfgEngine        :: EngineConfig
  , cfgLogLevel      :: LogLevel
  } deriving stock (Show, Generic)

-- | YAML-level configuration (no private key).
data ConfigFile = ConfigFile
  { cfNetwork       :: Network
  , cfApiUrl        :: T.Text
  , cfWsUrl         :: T.Text
  , cfWalletAddress :: T.Text
  , cfRisk          :: RiskLimits
  , cfEngine        :: EngineConfig
  , cfLogging       :: LoggingConfig
  } deriving stock (Show, Generic)

instance FromJSON ConfigFile where
  parseJSON = withObject "ConfigFile" $ \o ->
    ConfigFile
      <$> o .:  "network"
      <*> o .:  "apiUrl"
      <*> o .:  "wsUrl"
      <*> o .:? "walletAddress" .!= ""
      <*> o .:  "risk"
      <*> o .:? "engine" .!= defaultEngineConfig
      <*> o .:? "logging" .!= LoggingConfig Info

newtype LoggingConfig = LoggingConfig
  { lcLevel :: LogLevel
  } deriving stock (Show, Generic)

instance FromJSON LoggingConfig where
  parseJSON = withObject "LoggingConfig" $ \o ->
    LoggingConfig <$> o .:? "level" .!= Info

-- ---------------------------------------------------------------------------
-- Defaults
-- ---------------------------------------------------------------------------

defaultEngineConfig :: EngineConfig
defaultEngineConfig = EngineConfig
  { ecEventQueueSize      = 4096
  , ecOrderPollIntervalMs = 2000
  , ecHeartbeatIntervalMs = 1000
  }

-- ---------------------------------------------------------------------------
-- Loading
-- ---------------------------------------------------------------------------

-- | Load configuration from a YAML file.
-- The private key is read from the @HYPELL_PRIVATE_KEY@ environment variable.
loadConfig :: FilePath -> IO Config
loadConfig path = do
  cf <- Yaml.decodeFileThrow path :: IO ConfigFile
  mKey <- lookupEnv "HYPELL_PRIVATE_KEY"
  case mKey of
    Nothing -> error "HYPELL_PRIVATE_KEY environment variable is not set"
    Just k  -> pure Config
      { cfgNetwork       = cfNetwork cf
      , cfgApiUrl        = cfApiUrl cf
      , cfgWsUrl         = cfWsUrl cf
      , cfgPrivateKey    = TE.encodeUtf8 (T.pack k)
      , cfgWalletAddress = cfWalletAddress cf
      , cfgRisk          = cfRisk cf
      , cfgEngine        = cfEngine cf
      , cfgLogLevel      = lcLevel (cfLogging cf)
      }
