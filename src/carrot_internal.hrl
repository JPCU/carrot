%%
%% Common internal stuff
%%

-define(LOG_DEBUG(Format),      error_logger:info_msg(Format)).
-define(LOG_INFO(Format), error_logger:info_msg(Format)).
-define(LOG_INFO(Format, Args), error_logger:info_msg(Format, Args)).
-define(LOG_WARN(Format, Args), error_logger:warning_msg(Format, Args)).
-define(LOG_ERR(Format, Args),  error_logger:error_msg(Format, Args)).

