import Kue.Lattice

namespace Kue

inductive ManifestError where
  | contradiction
  | incomplete (value : Value)
  | ambiguous (alternatives : List (Mark × Value))
deriving Repr, BEq

def liveAlternatives (alternatives : List (Mark × Value)) : List (Mark × Value) :=
  (flattenAlternatives alternatives).filter fun alternative => !isBottom alternative.snd

def defaultAlternatives (alternatives : List (Mark × Value)) : List (Mark × Value) :=
  alternatives.filter fun alternative => alternative.fst == .default

def manifestCore : Value -> Except ManifestError Prim
  | .prim prim => .ok prim
  | .bottom => .error .contradiction
  | .top => .error (.incomplete .top)
  | .kind kind => .error (.incomplete (.kind kind))
  | .disj alternatives => .error (.ambiguous alternatives)

def manifest : Value -> Except ManifestError Prim
  | .prim prim => .ok prim
  | .bottom => .error .contradiction
  | .top => .error (.incomplete .top)
  | .kind kind => .error (.incomplete (.kind kind))
  | .disj alternatives =>
      let live := liveAlternatives alternatives
      let defaults := defaultAlternatives live
      match defaults with
      | [(_, value)] => manifestCore value
      | [] =>
          match live with
          | [(.regular, value)] => manifestCore value
          | alternatives => .error (.ambiguous alternatives)
      | alternatives => .error (.ambiguous alternatives)

end Kue
