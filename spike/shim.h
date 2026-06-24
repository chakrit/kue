#ifndef KUE_SPIKE_SHIM_H
#define KUE_SPIKE_SHIM_H

/* Initialize the Lean runtime + the Spike/Kue module init chain. Call once. */
void kue_init(void);

/* Evaluate a CUE source string through Kue's real evaluator. Returns a
   heap-allocated C string the caller must release with kue_free_c. */
char *kue_eval_c(const char *s);

/* Free a string returned by kue_eval_c. */
void kue_free_c(char *p);

#endif /* KUE_SPIKE_SHIM_H */
