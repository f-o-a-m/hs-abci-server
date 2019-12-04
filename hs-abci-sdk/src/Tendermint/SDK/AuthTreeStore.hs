module Tendermint.SDK.AuthTreeStore
  ( AuthTreeState(..)
  , initAuthTreeState
  , evalMergeScopes
  , eval
  ) where

import           Control.Concurrent.STM           (atomically)
import           Control.Concurrent.STM.TVar
import           Control.Monad                    (forM_)
import           Control.Monad.IO.Class
import qualified Crypto.Data.Auth.Tree            as AT
import qualified Crypto.Data.Auth.Tree.Class      as AT
import qualified Crypto.Data.Auth.Tree.Cryptonite as Cryptonite
import qualified Crypto.Hash                      as Cryptonite
import           Data.ByteArray                   (convert)
import           Data.ByteString                  (ByteString)
import qualified Data.List.NonEmpty               as NE
import           Polysemy                         (Embed, Member, Members, Sem,
                                                   interpret)
import           Polysemy.Reader                  (Reader, ask)
import           Polysemy.Tagged                  (Tagged (..))
import           Tendermint.SDK.Store             (ConnectionScope (..),
                                                   MergeScopes (..),
                                                   RawStore (..), StoreKey (..))

-- At the moment, the 'AuthTreeStore' is our only interpreter for the 'RawStore' effect.
-- It is an in memory merklized key value store. You can find the repository here
-- https://github.com/oscoin/avl-auth

newtype AuthTreeHash =  AuthTreeHash (Cryptonite.Digest Cryptonite.SHA256)

instance AT.MerkleHash AuthTreeHash where
    emptyHash = AuthTreeHash Cryptonite.emptyHash
    hashLeaf k v = AuthTreeHash $ Cryptonite.hashLeaf k v
    concatHashes (AuthTreeHash a) (AuthTreeHash b) = AuthTreeHash $ Cryptonite.concatHashes a b

data AuthTree (c :: ConnectionScope) = AuthTree
  { treeVar :: TVar (NE.NonEmpty (AT.Tree ByteString ByteString))
  }

initAuthTree :: IO (AuthTree c)
initAuthTree = AuthTree <$> newTVarIO (pure AT.empty)

evalTagged
  :: Member (Embed IO) r
  => AuthTree c
  -> Sem (Tagged c RawStore ': r) a
  -> Sem r a
evalTagged AuthTree{treeVar} =
  interpret
    (\(Tagged action) -> case action of
      RawStorePut (StoreKey sk) k v -> liftIO . atomically $ do
        tree NE.:| ts <- readTVar treeVar
        writeTVar treeVar $ AT.insert (sk <> k) v tree NE.:| ts
      RawStoreGet (StoreKey sk) k -> liftIO . atomically $ do
        tree NE.:| _ <- readTVar treeVar
        pure $ AT.lookup (sk <> k) tree
      RawStoreProve _ _ -> pure Nothing
      RawStoreDelete (StoreKey sk) k -> liftIO . atomically $ do
        tree NE.:| ts <- readTVar treeVar
        writeTVar treeVar $ AT.delete (sk <> k) tree NE.:| ts
      RawStoreRoot -> liftIO . atomically $ do
        tree NE.:| _ <- readTVar treeVar
        let AuthTreeHash hash = AT.merkleHash tree
        pure $ convert hash
      RawStoreBeginTransaction -> liftIO . atomically $ do
        tree NE.:| ts <- readTVar treeVar
        writeTVar treeVar $ tree NE.:| tree : ts
      RawStoreRollback -> liftIO . atomically $ do
        trees <- readTVar treeVar
        writeTVar treeVar $ case trees of
          t NE.:| []      -> t NE.:| []
          _ NE.:| t' : ts ->  t' NE.:| ts
      RawStoreCommit -> liftIO . atomically $ do
        trees <- readTVar treeVar
        writeTVar treeVar $ case trees of
          t NE.:| []     -> t NE.:| []
          t NE.:| _ : ts ->  t NE.:| ts
    )

data AuthTreeState = AuthTreeState
  { query     :: AuthTree 'Query
  , mempool   :: AuthTree 'Mempool
  , consensus :: AuthTree 'Consensus
  }

initAuthTreeState :: IO AuthTreeState
initAuthTreeState = AuthTreeState <$> initAuthTree <*> initAuthTree <*> initAuthTree

eval
  :: Members [Reader AuthTreeState, Embed IO] r
  => Sem (Tagged 'Query RawStore ': Tagged 'Mempool RawStore ': Tagged 'Consensus RawStore ': r) a
  -> Sem r a
eval m = do
  AuthTreeState{query, mempool, consensus} <- ask
  evalTagged consensus . evalTagged mempool. evalTagged query $ m

evalMergeScopes
  :: Members [Reader AuthTreeState,  Embed IO] r
  => Sem (MergeScopes ': r) a
  -> Sem r a
evalMergeScopes =
  interpret
    (\case
      MergeScopes -> do
        AuthTreeState{query, mempool, consensus} <- ask
        liftIO . atomically $ do
          let AuthTree queryV = query
              AuthTree mempoolV = mempool
              AuthTree consensusV = consensus
          consensusTrees <- readTVar consensusV
          let t = NE.last consensusTrees
          forM_ [queryV, mempoolV, consensusV] $ \v ->
            writeTVar v $ pure t
    )
