{-# LANGUAGE TemplateHaskell      #-}
{-# LANGUAGE UndecidableInstances #-}
{-# OPTIONS_GHC -fno-warn-orphans #-}

module Tendermint.SDK.BaseApp.CoreEff
  ( CoreEffs
  , Context(..)
  , contextLogConfig
  , contextPrometheusEnv
  , contextVersion
  , contextGrpcClient
  , makeContext
  , runCoreEffs
  ) where

import           Control.Lens                              (makeLenses, over,
                                                            view)
import           Data.Text                                 (Text)
import qualified Katip                                     as K
import           Polysemy                                  (Embed, Members, Sem,
                                                            runM)
import           Polysemy.Error                            (Error, runError)
import           Polysemy.Reader                           (Reader, asks, local,
                                                            runReader)
import           Tendermint.SDK.BaseApp.Errors             (AppError)
import qualified Tendermint.SDK.BaseApp.Logger.Katip       as KL
import qualified Tendermint.SDK.BaseApp.Metrics.Prometheus as P
import qualified Tendermint.SDK.BaseApp.Store.IAVLStore    as IAVL

-- | CoreEffs is one level below BaseAppEffs, and provides one possible
-- | interpretation for its effects to IO.
type CoreEffs =
  '[ Reader KL.LogConfig
   , Reader (Maybe P.PrometheusEnv)
   , Reader IAVL.IAVLVersion
   , Reader IAVL.GrpcClient
   , Error AppError
   , Embed IO
   ]

instance (Members CoreEffs r) => K.Katip (Sem r)  where
  getLogEnv = asks $ view KL.logEnv
  localLogEnv f m = local (over KL.logEnv f) m

instance (Members CoreEffs r) => K.KatipContext (Sem r) where
  getKatipContext = asks $ view KL.logContext
  localKatipContext f m = local (over KL.logContext f) m
  getKatipNamespace = asks $ view KL.logNamespace
  localKatipNamespace f m = local (over KL.logNamespace f) m

-- | 'Context' is the environment required to run 'CoreEffs' to 'IO'
data Context = Context
  { _contextLogConfig     :: KL.LogConfig
  , _contextPrometheusEnv :: Maybe P.PrometheusEnv
  , _contextGrpcClient    :: IAVL.GrpcClient
  , _contextVersion       :: IAVL.IAVLVersion
  }

makeLenses ''Context

makeContext
  :: KL.InitialLogNamespace
  -> Maybe P.MetricsScrapingConfig
  -> IAVL.IAVLVersion
  -> IO Context
makeContext KL.InitialLogNamespace{..} scrapingCfg version = do
  metCfg <- case scrapingCfg of
        Nothing -> pure Nothing
        Just scfg -> P.emptyState >>= \es ->
          pure . Just $ P.PrometheusEnv es scfg
  logCfg <- mkLogConfig _initialLogEnvironment _initialLogProcessName
  grpc <- IAVL.initGrpcClient
  pure $ Context
    { _contextLogConfig = logCfg
    , _contextPrometheusEnv = metCfg
    , _contextVersion = version
    , _contextGrpcClient = grpc
    }
    where
      mkLogConfig :: Text -> Text -> IO KL.LogConfig
      mkLogConfig env pName = do
        let mkLogEnv = K.initLogEnv (K.Namespace [pName]) (K.Environment env)
        le <- mkLogEnv
        return $ KL.LogConfig
          { _logNamespace = mempty
          , _logContext = mempty
          , _logEnv = le
          }

-- | The standard interpeter for 'CoreEffs'.
runCoreEffs
  :: Context
  -> forall a. Sem CoreEffs a -> IO (Either AppError a)
runCoreEffs Context{..} =
  runM .
    runError .
    runReader _contextGrpcClient .
    runReader _contextVersion .
    runReader _contextPrometheusEnv .
    runReader _contextLogConfig
