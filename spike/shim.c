#include <lean/lean.h>
#include <stdlib.h>
#include <string.h>
#include "shim.h"

/* In Lean 4.29 these are NOT declared in the public lean.h — the generated
   Main.c declares them inline before main(). We mirror that. A borrowed arg
   (`@& String`) has the same C type `lean_object*`; borrowing is a calling
   convention, not a distinct C type in this toolchain. */
void lean_initialize_runtime_module(void);
void lean_init_task_manager(void);

/* The @[export] symbol and the module-init function for the Spike module.
   The init ABI is a single `uint8_t builtin` (no world). The package-name
   prefix (`spike_`) is part of the generated symbol; `initialize_spike_Spike`
   transitively inits Kue and its dependencies (they must be in the link).
   kue_spike_eval OWNS its String argument (consumes it). */
extern lean_object *kue_spike_eval(lean_object *);
extern lean_object *initialize_spike_Spike(uint8_t builtin);

void kue_init(void) {
  lean_initialize_runtime_module();
  lean_object *r = initialize_spike_Spike(1 /* builtin */);
  if (lean_io_result_is_error(r)) {
    lean_io_result_show_error(r);
  }
  lean_dec_ref(r);
  lean_io_mark_end_initialization();
  lean_init_task_manager();
}

char *kue_eval_c(const char *s) {
  lean_object *in = lean_mk_string(s);
  /* kue_spike_eval OWNS (consumes) `in` — do NOT dec it here, or it's a
     double-free. `out` is owned by us and must be dec'd after we copy out. */
  lean_object *out = kue_spike_eval(in);
  char *res = strdup(lean_string_cstr(out));
  lean_dec(out);
  return res;
}

void kue_free_c(char *p) { free(p); }
