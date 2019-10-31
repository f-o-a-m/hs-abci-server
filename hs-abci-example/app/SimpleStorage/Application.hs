{-# LANGUAGE UndecidableInstances #-}

module SimpleStorage.Application
  ( AppError(..)
  , AppConfig(..)
  , makeAppConfig
  , Handler
  , runHandler
  ) where

import           Control.Exception                    (Exception)
import           Control.Monad.Catch                  (throwM)
import           Polysemy
import           Polysemy.Error
import           Polysemy.Output
import           Polysemy.Reader
import           SimpleStorage.Modules.SimpleStorage  as SimpleStorage
import           Tendermint.SDK.AuthTreeStore
import           Tendermint.SDK.Logger                as Logger
import           Tendermint.SDK.Store

data AppConfig = AppConfig
  { logConfig      :: Logger.LogConfig
  , authTreeDriver :: AuthTreeDriver
  }

makeAppConfig :: Logger.LogConfig -> IO AppConfig
makeAppConfig logCfg = do
  authTreeD <- initAuthTreeDriver
  pure $ AppConfig { logConfig = logCfg
                   , authTreeDriver = authTreeD
                   }

--------------------------------------------------------------------------------

data AppError = AppError String deriving (Show)

instance Exception AppError

type EffR =
  [ SimpleStorage.SimpleStorage
  , Output SimpleStorage.Event
  , RawStore
  , Logger
  , Error AppError
  , Reader LogConfig
  , Embed IO
  ]

type Handler = Sem EffR

-- NOTE: this should probably go in the library
runHandler
  :: AppConfig
  -> Handler a
  -> IO a
runHandler AppConfig{logConfig} m = do
  authTreeD <- initAuthTreeDriver
  eRes <- runM .
    runReader logConfig .
    runError .
    Logger.evalKatip .
    interpretAuthTreeStore authTreeD .
    ignoreOutput @SimpleStorage.Event .
    SimpleStorage.eval $ m
  case eRes of
    Left e  -> throwM e
    Right a -> pure a
  