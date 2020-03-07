------------------------------------------------------------------------
-- |
-- Module      : What4.SWord
-- Copyright   : Galois, Inc. 2018
-- License     : BSD3
-- Maintainer  : sweirich@galois.com
-- Stability   : experimental
-- Portability : non-portable (language extensions)
--
-- A wrapper for What4 bitvectors so that the width is not tracked
-- statically.
------------------------------------------------------------------------

{-# LANGUAGE ConstraintKinds #-}
{-# LANGUAGE DataKinds #-}
{-# LANGUAGE DeriveTraversable #-}
{-# LANGUAGE DeriveFoldable #-}
{-# LANGUAGE DeriveFunctor #-}
{-# LANGUAGE DoAndIfThenElse #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE GADTs #-}
{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE PatternGuards #-}
{-# LANGUAGE PolyKinds #-}
{-# LANGUAGE RankNTypes #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TypeFamilies #-}
{-# LANGUAGE TypeOperators #-}
{-# LANGUAGE TypeApplications #-}
{-# LANGUAGE PartialTypeSignatures #-}

-- To allow implicitly provided nats
{-# LANGUAGE AllowAmbiguousTypes #-}


-- TODO: module exports?
module What4.SWord
  ( SWord(..)
  , bvAsSignedInteger
  , bvAsUnsignedInteger
  , integerToBV
  , bvToInteger
  , sbvToInteger
  , bvWidth
  , bvLit
  , bvFill
  , bvAt
  , bvSet
  , bvJoin
  , bvSlice
  , bvIte
  , bvPack
  , bvUnpack
  , bvForall
  , unsignedBVBounds
  , signedBVBounds

    -- * Logic operations
  , bvNot
  , bvAnd
  , bvOr
  , bvXor

    -- * Arithmetic operations
  , bvNeg
  , bvAdd
  , bvSub
  , bvMul
  , bvUDiv
  , bvURem
  , bvSDiv
  , bvSRem

    -- * Comparison operations
  , bvEq
  , bvsle
  , bvslt
  , bvule
  , bvult
  , bvsge
  , bvsgt
  , bvuge
  , bvugt
  , bvIsNonzero

    -- * bit-counting operations
  , bvPopcount
  , bvCountLeadingZeros
  , bvCountTrailingZeros
  , bvLg2

    -- * Shift and rotates
  , bvShl
  , bvLshr
  , bvAshr
  , bvRol
  , bvRor

    -- * Move this?
  , showVec
  ) where


-- TODO: improve treatment of partiality. Currently, dynamic
-- failures (e.g. due to failing width checks) use 'fail' from
-- the IO monad. Perhaps this is what we want, as the saw-core
-- code should come in type checked.

import           Data.Vector (Vector)
import qualified Data.Vector as V
import           Numeric.Natural
import qualified Text.PrettyPrint.ANSI.Leijen as PP

import           GHC.TypeNats

import           Data.Parameterized.NatRepr
import           Data.Parameterized.Some(Some(..))

import           What4.Interface(SymBV,Pred,SymInteger,IsExpr,SymExpr,IsExprBuilder)
import qualified What4.Interface as W

-------------------------------------------------------------
--
-- | A What4 symbolic bitvector where the size does not appear in the type
data SWord sym where

  DBV :: (IsExpr (SymExpr sym), 1<=w) => SymBV sym w -> SWord sym
  -- a bit-vector with positive length

  ZBV :: SWord sym
  -- a zero-length bit vector. i.e. 0


instance Show (SWord sym) where
  show (DBV bv) = show $ W.printSymExpr bv
  show ZBV      = "0:[0]"

-------------------------------------------------------------

-- | Return the signed value if this is a constant bitvector
bvAsSignedInteger :: forall sym. IsExprBuilder sym => SWord sym -> Maybe Integer
bvAsSignedInteger ZBV = Just 0
bvAsSignedInteger (DBV (bv :: SymBV sym w)) =
  W.asSignedBV bv

-- | Return the unsigned value if this is a constant bitvector
bvAsUnsignedInteger :: forall sym. IsExprBuilder sym => SWord sym -> Maybe Integer
bvAsUnsignedInteger ZBV = Just 0
bvAsUnsignedInteger (DBV (bv :: SymBV sym w)) =
  W.asUnsignedBV bv


unsignedBVBounds :: forall sym. IsExprBuilder sym => SWord sym -> Maybe (Integer, Integer)
unsignedBVBounds ZBV = Just (0, 0)
unsignedBVBounds (DBV bv) = W.unsignedBVBounds bv

signedBVBounds :: forall sym. IsExprBuilder sym => SWord sym -> Maybe (Integer, Integer)
signedBVBounds ZBV = Just (0, 0)
signedBVBounds (DBV bv) = W.signedBVBounds bv


-- | Convert an integer to an unsigned bitvector.
--   Result is undefined if integer is outside of range.
integerToBV :: forall sym width. (Integral width, IsExprBuilder sym) =>
  sym ->  SymInteger sym -> width -> IO (SWord sym)
integerToBV sym i w
  | Just (Some wr) <- someNat w
  , Just LeqProof  <- isPosNat wr
  = DBV <$> W.integerToBV sym i wr
  | 0 == toInteger w
  = return ZBV
  | otherwise
  = fail "integerToBV: invalid arg"

-- | Interpret the bit-vector as an unsigned integer
bvToInteger :: forall sym. (IsExprBuilder sym) =>
  sym -> SWord sym -> IO (SymInteger sym)
bvToInteger sym ZBV      = W.intLit sym 0
bvToInteger sym (DBV bv) = W.bvToInteger sym bv

-- | Interpret the bit-vector as a signed integer
sbvToInteger :: forall sym. (IsExprBuilder sym) =>
  sym -> SWord sym -> IO (SymInteger sym)
sbvToInteger sym ZBV      = W.intLit sym 0
sbvToInteger sym (DBV bv) = W.sbvToInteger sym bv


-- | Get the width of a bitvector
bvWidth :: forall sym. SWord sym -> Integer
bvWidth (DBV x) = fromInteger (intValue (W.bvWidth x))
bvWidth ZBV = 0

-- | Create a bitvector with the given width and value
bvLit :: forall sym. IsExprBuilder sym =>
  sym -> Integer -> Integer -> IO (SWord sym)
bvLit _ w _
  | w == 0
  = return ZBV
bvLit sym w dat
  | Just (Some rw) <- someNat w
  , Just LeqProof <- isPosNat rw
  = DBV <$> W.bvLit sym rw dat
  | otherwise
  = fail "bvLit: size of bitvector is < 0 or >= maxInt"

bvFill :: forall sym. IsExprBuilder sym =>
  sym -> Integer -> Pred sym -> IO (SWord sym)
bvFill sym w p
  | w == 0
  = return ZBV

  | Just (Some rw) <- someNat w
  , Just LeqProof <- isPosNat rw
  = DBV <$> W.bvFill sym rw p

  | otherwise
  = fail "bvFill size of bitvector is < 0 or >= maxInt"


-- | Returns true if the corresponding bit in the bitvector is set.
--   NOTE bits are numbered in big-endian ordering, meaning the
--   most-significant bit is bit 0
bvAt :: forall sym.
  IsExprBuilder sym =>
  sym ->
  SWord sym ->
  Integer {- ^ Index of bit (0 is the most significant bit) -} ->
  IO (Pred sym)
bvAt sym (DBV bv) i = do
  let w   = natValue (W.bvWidth bv)
  let idx = w - 1 - fromInteger i
  W.testBitBV sym idx bv
bvAt _ ZBV _ = fail "cannot index into empty bitvector"
  -- TODO: or could return 0?


-- | Set the numbered bit in the given bitvector to the given
--   bit value.
--   NOTE bits are numbered in big-endian ordering, meaning the
--   most-significant bit is bit 0
bvSet :: forall sym.
  IsExprBuilder sym =>
  sym ->
  SWord sym ->
  Integer {- ^ Index of bit (0 is the most significant bit) -} ->
  Pred sym ->
  IO (SWord sym)
bvSet _ ZBV _ _ = return ZBV
bvSet sym (DBV bv) i b =
  do let w = natValue (W.bvWidth bv)
     let idx = w - 1 - fromInteger i
     DBV <$> W.bvSet sym bv idx b

-- | Concatenate two bitvectors.
bvJoin  :: forall sym. IsExprBuilder sym => sym
  -> SWord sym
  -- ^ most significant bits
  -> SWord sym
  -- ^ least significant bits
  -> IO (SWord sym)
bvJoin _ x ZBV = return x
bvJoin _ ZBV x = return x
bvJoin sym (DBV bv1) (DBV bv2)
  | LeqProof <- leqAddPos (W.bvWidth bv1) (W.bvWidth bv2)
  = DBV <$> W.bvConcat sym bv1 bv2

-- | Select a subsequence from a bitvector.
-- idx = w - (m + n)
-- This fails if idx + n is >= w
bvSlice :: forall sym. IsExprBuilder sym => sym
  -> Integer
  -- ^ Starting index, from 0 as most significant bit
  -> Integer
  -- ^ Number of bits to take (must be > 0)
  -> SWord sym -> IO (SWord sym)
bvSlice sym m n (DBV bv)
  | Just (Some nr) <- someNat n,
    Just LeqProof  <- isPosNat nr,
    Just (Some mr) <- someNat m,
    let wr = W.bvWidth bv,
    Just LeqProof <- testLeq (addNat mr nr)  wr,
    let idx = subNat wr (addNat mr nr),
    Just LeqProof <- testLeq (addNat idx nr) wr
  = DBV <$> W.bvSelect sym idx nr bv
  | otherwise
  = fail $
      "invalid arguments to slice: " ++ show m ++ " " ++ show n
        ++ " from vector of length " ++ show (W.bvWidth bv)
bvSlice _ _ _ ZBV = return ZBV

-- | Ceiling (log_2 x)
-- adapted from saw-core-sbv/src/Verifier/SAW/Simulator/SBV.hs
w_bvLg2 :: forall sym w. (IsExprBuilder sym, 1 <= w) =>
   sym -> SymBV sym w -> IO (SymBV sym w)
w_bvLg2 sym x = go 0
  where
    w = W.bvWidth x
    size :: Integer
    size = intValue w
    lit :: Integer -> IO (SymBV sym w)
    lit n = W.bvLit sym w n
    go :: Integer -> IO (SymBV sym w)
    go i | i < size = do
           x' <- lit (2 ^ i)
           b' <- W.bvUle sym x x'
           th <- lit i
           el <- go (i + 1)
           W.bvIte sym b' th el
         | otherwise    = lit i

-- | If-then-else applied to bitvectors.
bvIte :: forall sym. IsExprBuilder sym =>
  sym -> Pred sym -> SWord sym -> SWord sym -> IO (SWord sym)
bvIte _ _ ZBV ZBV
  = return ZBV
bvIte sym p (DBV bv1) (DBV bv2)
  | Just Refl <- testEquality (W.exprType bv1) (W.exprType bv2)
  = DBV <$> W.bvIte sym p bv1 bv2
bvIte _ _ _ _
  = fail "bit-vectors don't have same length"


----------------------------------------------------------------------
-- Convert to/from Vectors
----------------------------------------------------------------------

-- | for debugging
showVec :: forall sym. (W.IsExpr (W.SymExpr sym)) => Vector (Pred sym) -> String
showVec vec =
  show (PP.list (V.toList (V.map W.printSymExpr vec)))

-- | explode a bitvector into a vector of booleans
bvUnpack :: forall sym. IsExprBuilder sym =>
  sym -> SWord sym -> IO (Vector (Pred sym))
bvUnpack _   ZBV = return V.empty
bvUnpack sym (DBV bv) = do
  let w :: Natural
      w = natValue (W.bvWidth bv)
  V.generateM (fromIntegral w)
              (\i -> W.testBitBV sym (w - 1 - fromIntegral i) bv)

-- | convert a vector of booleans to a bitvector
bvPack :: forall sym. (W.IsExpr (W.SymExpr sym), IsExprBuilder sym) =>
  sym -> Vector (Pred sym) -> IO (SWord sym)
bvPack sym vec = do
  vec' <- V.mapM (\p -> do
                     v1 <- bvLit sym 1 1
                     v2 <- bvLit sym 1 0
                     bvIte sym p v1 v2) vec
  V.foldM (\x y -> bvJoin sym x y) ZBV vec'

----------------------------------------------------------------------
-- Generic wrapper for unary operators
----------------------------------------------------------------------

-- | Type of unary operation on bitvectors
type SWordUn =
  forall sym. IsExprBuilder sym =>
  sym -> SWord sym -> IO (SWord sym)

-- | Convert a unary operation on length indexed bvs to a unary operation
-- on `SWord`
bvUn ::  forall sym. IsExprBuilder sym =>
   (forall w. 1 <= w => sym -> SymBV sym w -> IO (SymBV sym w)) ->
   sym -> SWord sym -> IO (SWord sym)
bvUn f sym (DBV bv) = DBV <$> f sym bv
bvUn _ _  ZBV = return ZBV

----------------------------------------------------------------------
-- Generic wrapper for binary operators that take two words
-- of the same length
----------------------------------------------------------------------

-- | type of binary operation that returns a bitvector
type SWordBin =
  forall sym. IsExprBuilder sym =>
  sym -> SWord sym -> SWord sym -> IO (SWord sym)
-- | type of binary operation that returns a boolean
type PredBin =
  forall sym. IsExprBuilder sym =>
  sym -> SWord sym -> SWord sym -> IO (Pred sym)


-- | convert binary operations that return bitvectors
bvBin  :: forall sym. IsExprBuilder sym =>
  (forall w. 1 <= w => sym -> SymBV sym w -> SymBV sym w -> IO (SymBV sym w)) ->
  sym -> SWord sym -> SWord sym -> IO (SWord sym)
bvBin f sym (DBV bv1) (DBV bv2)
  | Just Refl <- testEquality (W.exprType bv1) (W.exprType bv2)
  = DBV <$> f sym bv1 bv2
bvBin _ _ ZBV ZBV
  = return ZBV
bvBin _ _ _ _
  = fail "bit vectors must have same length"


-- | convert binary operations that return booleans (Pred)
bvBinPred  :: forall sym. IsExprBuilder sym =>
  (forall w. 1 <= w => sym -> SymBV sym w -> SymBV sym w -> IO (Pred sym)) ->
  sym -> SWord sym -> SWord sym -> IO (Pred sym)
bvBinPred f sym (DBV bv1) (DBV bv2)
  | Just Refl <- testEquality (W.exprType bv1) (W.exprType bv2)
  = f sym bv1 bv2
  | otherwise
  = fail $ "bit vectors must have same length" ++ show (W.bvWidth bv1) ++ " " ++ show (W.bvWidth bv2)
bvBinPred _ _ ZBV ZBV
  = fail "no zero-length bit vectors here"
bvBinPred _ _ _ _
  = fail $ "bit vectors must have same length"



 -- Bitvector logical

-- | Bitwise complement
bvNot :: SWordUn
bvNot = bvUn W.bvNotBits

-- | Bitwise logical and.
bvAnd :: SWordBin
bvAnd = bvBin W.bvAndBits

-- | Bitwise logical or.
bvOr :: SWordBin
bvOr = bvBin W.bvOrBits

-- | Bitwise logical exclusive or.
bvXor :: SWordBin
bvXor = bvBin W.bvXorBits

 -- Bitvector arithmetic

-- | 2's complement negation.
bvNeg :: SWordUn
bvNeg = bvUn W.bvNeg

-- | Add two bitvectors.
bvAdd :: SWordBin
bvAdd = bvBin W.bvAdd

-- | Subtract one bitvector from another.
bvSub :: SWordBin
bvSub = bvBin W.bvSub

-- | Multiply one bitvector by another.
bvMul :: SWordBin
bvMul = bvBin W.bvMul


bvPopcount :: SWordUn
bvPopcount = bvUn W.bvPopcount

bvCountLeadingZeros :: SWordUn
bvCountLeadingZeros = bvUn W.bvCountLeadingZeros

bvCountTrailingZeros :: SWordUn
bvCountTrailingZeros = bvUn W.bvCountTrailingZeros

bvForall :: W.IsSymExprBuilder sym =>
  sym -> Natural -> (SWord sym -> IO (Pred sym)) -> IO (Pred sym)
bvForall sym n f =
  case W.userSymbol "i" of
    Left err -> fail $ show err
    Right indexSymbol ->
      case mkNatRepr n of
        Some w
          | Just LeqProof <- testLeq (knownNat @1) w ->
              do i <- W.freshBoundVar sym indexSymbol $ W.BaseBVRepr w
                 body <- f . DBV $ W.varExpr sym i
                 W.forallPred sym i body
          | otherwise -> f ZBV

-- | Unsigned bitvector division.
--
--   The result is undefined when @y@ is zero,
--   but is otherwise equal to @floor( x / y )@.
bvUDiv :: SWordBin
bvUDiv = bvBin W.bvUdiv


-- | Unsigned bitvector remainder.
--
--   The result is undefined when @y@ is zero,
--   but is otherwise equal to @x - (bvUdiv x y) * y@.
bvURem :: SWordBin
bvURem = bvBin W.bvUrem

-- | Signed bitvector division.  The result is truncated to zero.
--
--   The result of @bvSdiv x y@ is undefined when @y@ is zero,
--   but is equal to @floor(x/y)@ when @x@ and @y@ have the same sign,
--   and equal to @ceiling(x/y)@ when @x@ and @y@ have opposite signs.
--
--   NOTE! However, that there is a corner case when dividing @MIN_INT@ by
--   @-1@, in which case an overflow condition occurs, and the result is instead
--   @MIN_INT@.
bvSDiv :: SWordBin
bvSDiv = bvBin W.bvSdiv

-- | Signed bitvector remainder.
--
--   The result of @bvSrem x y@ is undefined when @y@ is zero, but is
--   otherwise equal to @x - (bvSdiv x y) * y@.
bvSRem :: SWordBin
bvSRem = bvBin W.bvSrem

bvLg2 :: SWordUn
bvLg2 = bvUn w_bvLg2

 -- Bitvector comparisons

-- | Return true if bitvectors are equal.
bvEq   :: PredBin
bvEq = bvBinPred W.bvEq

-- | Signed less-than-or-equal.
bvsle  :: PredBin
bvsle = bvBinPred W.bvSle

-- | Signed less-than.
bvslt  :: PredBin
bvslt = bvBinPred W.bvSlt

-- | Unsigned less-than-or-equal.
bvule  :: PredBin
bvule = bvBinPred W.bvUle

-- | Unsigned less-than.
bvult  :: PredBin
bvult = bvBinPred W.bvUlt

-- | Signed greater-than-or-equal.
bvsge  :: PredBin
bvsge = bvBinPred W.bvSge

-- | Signed greater-than.
bvsgt  :: PredBin
bvsgt = bvBinPred W.bvSgt

-- | Unsigned greater-than-or-equal.
bvuge  :: PredBin
bvuge = bvBinPred W.bvUge

-- | Unsigned greater-than.
bvugt  :: PredBin
bvugt = bvBinPred W.bvUgt

bvIsNonzero :: IsExprBuilder sym => sym -> SWord sym -> IO (Pred sym)
bvIsNonzero sym ZBV = return (W.falsePred sym)
bvIsNonzero sym (DBV x) = W.bvIsNonzero sym x


----------------------------------------
-- Bitvector shifts and rotates
----------------------------------------

bvMax ::
  (IsExprBuilder sym, 1 <= w) =>
  sym ->
  W.SymBV sym w ->
  W.SymBV sym w ->
  IO (W.SymBV sym w)
bvMax sym x y =
  do p <- W.bvUge sym x y
     W.bvIte sym p x y

reduceShift ::
  IsExprBuilder sym =>
  (forall w. (1 <= w) => sym -> W.SymBV sym w -> W.SymBV sym w -> IO (W.SymBV sym w)) ->
  sym -> SWord sym -> SWord sym -> IO (SWord sym)
reduceShift _wop _sym ZBV _ = return ZBV
reduceShift _wop _sym x ZBV = return x
reduceShift wop sym (DBV x) (DBV y) =
  case compareNat (W.bvWidth x) (W.bvWidth y) of

    -- already the same size, apply the operation
    NatEQ -> DBV <$> wop sym x y

    -- y is shorter, zero extend
    NatGT _diff ->
      do y' <- W.bvZext sym (W.bvWidth x) y
         DBV <$> wop sym x y'

    -- y is longer, clamp to the width of x then truncate.
    -- Truncation is OK because the value will always fit after
    -- clamping.
    NatLT _diff ->
      do wx <- W.bvLit sym (W.bvWidth y) (intValue (W.bvWidth x))
         y' <- W.bvTrunc sym (W.bvWidth x) =<< bvMax sym y wx
         DBV <$> wop sym x y'

reduceRotate ::
  IsExprBuilder sym =>
  (forall w. (1 <= w) => sym -> W.SymBV sym w -> W.SymBV sym w -> IO (W.SymBV sym w)) ->
  sym -> SWord sym -> SWord sym -> IO (SWord sym)
reduceRotate _wop _sym ZBV _ = return ZBV
reduceRotate _wop _sym x ZBV = return x
reduceRotate wop sym (DBV x) (DBV y) =
  case compareNat (W.bvWidth x) (W.bvWidth y) of

    -- already the same size, apply the operation
    NatEQ -> DBV <$> wop sym x y

    -- y is shorter, zero extend
    NatGT _diff ->
      do y' <- W.bvZext sym (W.bvWidth x) y
         DBV <$> wop sym x y'

    -- y is longer, reduce modulo the width of x, then truncate
    -- Truncation is OK because the value will always
    -- fit after modulo reduction
    NatLT _diff ->
      do wx <- W.bvLit sym (W.bvWidth y) (intValue (W.bvWidth x))
         y' <- W.bvTrunc sym (W.bvWidth x) =<< W.bvUrem sym y wx
         DBV <$> wop sym x y'

bvShl  :: W.IsExprBuilder sym => sym -> SWord sym -> SWord sym -> IO (SWord sym)
bvShl = reduceShift W.bvShl

bvLshr  :: W.IsExprBuilder sym => sym -> SWord sym -> SWord sym -> IO (SWord sym)
bvLshr = reduceShift W.bvLshr

bvAshr :: W.IsExprBuilder sym => sym -> SWord sym -> SWord sym -> IO (SWord sym)
bvAshr = reduceShift W.bvAshr

bvRol  :: W.IsExprBuilder sym => sym -> SWord sym -> SWord sym -> IO (SWord sym)
bvRol = reduceRotate W.bvRol

bvRor  :: W.IsExprBuilder sym => sym -> SWord sym -> SWord sym -> IO (SWord sym)
bvRor = reduceRotate W.bvRor