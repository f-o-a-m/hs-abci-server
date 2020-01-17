module Tendermint.SDK.BaseApp.Query.Delayed where

import           Control.Monad.Reader                 (MonadReader, ReaderT,
                                                       ask, runReaderT)
import           Control.Monad.Trans                  (MonadTrans (..))
import qualified Network.ABCI.Types.Messages.Request  as Request
import qualified Network.ABCI.Types.Messages.Response as Response
import           Polysemy                             (Sem)
import           Tendermint.SDK.BaseApp.Query.Types   (QueryError (..),
                                                       RouteResult (..),
                                                       RouteResultT (..))

--------------------------------------------------------------------------------
-- NOTE: most of this was vendored and repurposed from servant


newtype DelayedM m a =
  DelayedM { runDelayedM' :: ReaderT Request.Query (RouteResultT m) a }
    deriving (Functor, Applicative, Monad, MonadReader Request.Query)

liftRouteResult :: Monad m => RouteResult a -> DelayedM m a
liftRouteResult x = DelayedM $ lift $ RouteResultT . return $ x

runDelayedM :: DelayedM m a -> Request.Query -> m (RouteResult a)
runDelayedM m req = runRouteResultT $ runReaderT (runDelayedM' m) req

--------------------------------------------------------------------------------

data Delayed m env a where
  Delayed :: { delayedQueryArgs :: env -> DelayedM m qa
             , delayedParams :: DelayedM m params
             , delayedHandler :: qa -> params -> Request.Query -> RouteResult a
             } -> Delayed m env a

instance Functor m => Functor (Delayed m env) where
  fmap f Delayed{..} =
    Delayed { delayedHandler = \qa params q -> f <$> delayedHandler qa params q
            , ..
            }

runDelayed
  :: Monad m
  => Delayed m env a
  -> env
  -> Request.Query
  -> m (RouteResult a)
runDelayed Delayed{..} env = runDelayedM (do
    q <- ask
    qa <- delayedQueryArgs env
    params <- delayedParams
    liftRouteResult $ delayedHandler qa params q
  )

runAction
  :: Delayed (Sem r) env (Sem r a)
  -> env
  -> Request.Query
  -> (a -> RouteResult Response.Query)
  -> Sem r (RouteResult Response.Query)
runAction action env query k = do
    res <- runDelayed action env query
    case res of
      Route a     -> k <$> a
      Fail e      -> pure $ Fail e
      FailFatal e -> pure $ FailFatal e

-- | Fail with the option to recover.
delayedFail :: Monad m => QueryError -> DelayedM m a
delayedFail err = liftRouteResult $ Fail err

addQueryArgs
  :: Monad m
  => Delayed m env (a -> b)
  -> (qa -> DelayedM m a)
  -> Delayed m (qa, env) b
addQueryArgs Delayed{..} new =
  Delayed
    { delayedQueryArgs = \ (qa, env) -> (,) <$> delayedQueryArgs env <*> new qa
    , delayedHandler   = \ (x, v) params query -> ($ v) <$> delayedHandler x params query
    , ..
    }

addParameter
  :: Monad m
  => Delayed m env (a -> b)
  -> DelayedM m a
  -> Delayed m env b
addParameter Delayed {..} new =
  Delayed
    { delayedParams = (,) <$> delayedParams <*> new
    , delayedHandler = \qa (p, pNew) query -> ($ pNew) <$> delayedHandler qa p query
    , ..
    }

emptyDelayed :: Monad m => RouteResult a -> Delayed m b a
emptyDelayed response =
  let r = pure ()
  in Delayed (const r) r $ \_ _ _ -> response

-- | Gain access to the incoming request.
withQuery
  :: Monad m
  => (Request.Query -> DelayedM m a)
  -> DelayedM m a
withQuery f = do
  req <- ask
  f req
