#ifndef tweakloader_h
#define tweakloader_h

#include <stdbool.h>

bool tweakloader_apply_in_session(void);
bool tweakloader_stop_in_session(void);
void tweakloader_forget_remote_state(void);
void tweakloader_reload_list(void);
unsigned int tweakloader_loaded_count(void);

#endif
