import Kue.Lattice

namespace Kue

theorem meet_top_left (value : Value) : meet .top value = value := by
  cases value <;> rfl

theorem meet_bottom_left (value : Value) : meet .bottom value = .bottom := by
  cases value <;> rfl

theorem join_bottom_left (value : Value) : join .bottom value = value := by
  cases value <;> rfl

theorem join_top_left (value : Value) : join .top value = .top := by
  cases value <;> rfl

theorem meet_identical_prim (prim : Prim) : meet (.prim prim) (.prim prim) = .prim prim := by
  cases prim <;> simp [meet, meetCore, meetPrim]

theorem meet_conflicting_ints :
    meet (.prim (.int 1)) (.prim (.int 2)) = .bottom := by
  rfl

theorem join_distinct_primitives_keeps_disjunction :
    join (.prim (.string "a")) (.prim (.string "b"))
      = .disj [(.regular, .prim (.string "a")), (.regular, .prim (.string "b"))] := by
  rfl

theorem meet_disjunction_distributes_and_removes_bottom :
    meet
      (.disj [(.regular, .prim (.string "a")), (.regular, .prim (.int 1))])
      (.kind .string)
      = .prim (.string "a") := by
  rfl

theorem meet_disjunction_preserves_default_marker :
    meet
      (.disj [(.default, .prim (.int 1)), (.regular, .prim (.string "a"))])
      (.kind .int)
      = .disj [(.default, .prim (.int 1))] := by
  rfl

#guard meet (.kind .int) (.prim (.int 1)) == .prim (.int 1)
#guard meet (.prim (.string "a")) (.prim (.string "b")) == .bottom
#guard join (.prim (.int 1)) (.prim (.int 2))
  == .disj [(.regular, .prim (.int 1)), (.regular, .prim (.int 2))]

end Kue
