#ifndef barmoji_h
#define barmoji_h

#include <stdbool.h>

bool barmoji_apply_in_session(void);
bool barmoji_stop_in_session(void);
void barmoji_configure(int yOffset, int widthPercent, int fontSize, int backgroundAlphaPercent);
void barmoji_configure_shared_snippets(const char *snippet1, const char *snippet2, const char *snippet3);
void barmoji_forget_remote_state(void);

#endif
