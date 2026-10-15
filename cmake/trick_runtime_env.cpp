// Supplies the environment a Trick sim expects (normally set by Trick's
// makefiles/shell), so the executable can be launched directly from any cwd.
#include <cstdlib>
#include <string>

namespace {
struct TrickRuntimeEnv {
    TrickRuntimeEnv()
    {
        setenv("TRICK_HOME", TRICK_RT_HOME, 0);
        setenv("TRICK_PYTHON_PATH", "", 0);

        // Trick only looks for trick.zip (and trick.zip/trick) in the cwd, after
        // its own pymods/trick package; PYTHONPATH entries come first, so the
        // sim's modules win.
        std::string path = TRICK_RT_TRICK_ZIP ":" TRICK_RT_TRICK_ZIP "/trick";
        if (const char* existing = std::getenv("PYTHONPATH"); existing && *existing) {
            path += ":";
            path += existing;
        }
        setenv("PYTHONPATH", path.c_str(), 1);
    }
} const trick_runtime_env;
} // namespace
