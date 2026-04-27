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
  simp [meet, meetPrim]

theorem meet_conflicting_ints :
    meet (.prim (.int 1)) (.prim (.int 2)) = .bottom := by
  rfl

#eval meet (.kind .int) (.prim (.int 1)) == .prim (.int 1)
#eval meet (.prim (.string "a")) (.prim (.string "b")) == .bottom

end Kue
