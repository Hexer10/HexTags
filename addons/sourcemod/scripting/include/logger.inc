enum LogLevel {
    NONE = 0,
    INFO = 1,
    DEBUG = 2
}

static LogLevel _level;

methodmap Logger {
    
    property LogLevel level 
    {
        public get() { return _level; }
        public set(LogLevel level) { _level = level; }
    }

    public void debug(const char[] format, any ...)
    {
        if (this.level < DEBUG)
            return;
        
        char buffer[512];
        VFormat(buffer, sizeof(buffer), format, 3);
        StrCat("DEBUG: ", sizeof(buffer), buffer);

        LogMessage(buffer);
    }

    public void info(const char[] format, any ...)
    {
        if (this.level < INFO)
            return;
        
        char buffer[512];
        VFormat(buffer, sizeof(buffer), format, 3);
        StrCat("INFO: ", sizeof(buffer), buffer);

        LogMessage(buffer);
    }
}