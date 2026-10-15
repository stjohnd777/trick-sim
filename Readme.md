# Cannonball Simulation with Trick and CMake

A small learning project based on NASA's [Trick simple simulation tutorial](https://nasa.github.io/trick/tutorial/ATutASimpleSim). It launches a cannonball in two dimensions, calculates its trajectory analytically under constant gravity, detects ground impact, and prints the final state.

The goal is to use [Trick](https://github.com/nasa/trick) through a familiar CMake workflow: treat an already-built Trick checkout as a dependency, build a named executable, and run it directly. Trick still provides the simulation executive, job scheduling, model introspection, and Python input processor.

The build and integration code use CMake and C++17. The cannon model currently remains in C, following the tutorial; it has not yet been rewritten as a C++ class.

## Building

### Prerequisites

- CMake 3.25 or newer.
- C and C++ compilers with C++17 support.
- An already-configured and built Trick checkout. This project requests Trick version 25 or newer, but has only been exercised with Trick 25.1.2-beta on Apple Silicon macOS.
- Trick's code-generation tools and their dependencies, including GNU Make, Perl, SWIG, and the Python interpreter used when Trick was built.
- Development libraries matching the Trick build: Python embedding support and UDUNITS2, plus GSL and HDF5 when enabled in Trick's configuration.

This project does not download, configure, or rebuild Trick. It expects the headers, static libraries, tools, and configuration files in the existing Trick tree to remain available.

### Default workflow

From this project's root directory:

```bash
cmake --preset default
cmake --build --preset default --parallel
```

The default preset in [CMakePresets.json](./CMakePresets.json) selects a Debug build, writes build products into `build/`, and uses:

```text
$HOME/development/github/trick
```

as the Trick checkout location. The resulting executable is `build/S_main`.

### Using a different Trick checkout

Override the preset's dependency path:

```bash
cmake --preset default -DTRICK_HOME=/absolute/path/to/trick
cmake --build --preset default --parallel
```

Alternatively, configure without presets:

```bash
cmake -S . -B build \
  -DTRICK_HOME=/absolute/path/to/trick \
  -DCMAKE_BUILD_TYPE=Debug
cmake --build build --parallel
```

The custom find module also accepts the `TRICK_HOME` environment variable when no CMake value is supplied. The default preset explicitly sets a value, so use `-DTRICK_HOME=...` to override it.

## Running the simulation

From the project root:

```bash
./build/S_main RUN_test/input.py
```

No environment setup script or separate Trick launcher is needed. The input script is executed by Trick's embedded Python interpreter, not by running Python separately.

The executable can also be launched from another working directory by providing absolute paths:

```bash
/absolute/path/to/SIM_cannon_analytic/build/S_main \
  /absolute/path/to/SIM_cannon_analytic/RUN_test/input.py
```

The supplied [input script](./RUN_test/input.py) contains:

```python
trick.stop(5.2)
```

This stops the executive at **5.2 seconds of simulation time**, not after 5.2 seconds of wall-clock time. The simulation is not configured to pace itself in real time.

### Debugging in VS Code

Install the **CodeLLDB** extension (`vadimcn.vscode-lldb`), then configure and build
the Debug preset using the build commands above. Open Run and Debug, select
**Debug cannon simulation**, and press **F5**.

The profile in [.vscode/launch.json](./.vscode/launch.json) launches `build/S_main`
with the supplied run input and the project root as its working directory.
Set a breakpoint inside `cannon_init` or `cannon_analytic` to inspect the model's
`C` pointer, position, velocity, and time. The simulation runs quickly, so set
breakpoints before launching.

The profile launches the existing executable; rebuild after changing compiled
source files. Debugging Trick's own internals also requires its libraries to have
been built with debug information.

### Expected output

With the default launch speed of **50 m/s**, launch angle of **30 degrees**, initial position of **[0, 0] m**, and gravity of **9.81 m/s²** downward, the significant output is:

```text
IMPACT: t = 5.096839959, pos[0] = 220.699644186

========================================
      Cannon Ball State at Shutdown
t = 5.2
pos = [220.699644186, 0.000000000]
vel = [0.000000000, 0.000000000]
========================================
```

Trick also prints termination diagnostics and runtime statistics. A normal run reports `Reached termination time`; this is expected, not a failure. Timing, memory statistics, timestamps, and interleaving of standard output and standard error can vary.

The ball stays at its impact position with zero velocity after landing. The simulation continues until the requested stop time.

### Changing the launch conditions

Edit the input script to override defaults before the initialization job runs. For example:

```python
dyn.cannon.init_speed = trick.attach_units("m/s", 50.0)
dyn.cannon.init_angle = trick.attach_units("d", 45.0)
trick.stop(8.0)
```

Here `"d"` denotes degrees; the stored angle is in radians. This launch should land at approximately **7.208020196 s**, with a range of **254.841997961 m**. Input-script changes do not require rebuilding.

## Project organization

```text
.
|-- CMakeLists.txt
|-- CMakePresets.json
|-- Readme.md
|-- S_define
|-- S_overrides.mk
|-- cmake/
|   |-- FindTrick.cmake
|   `-- trick_runtime_env.cpp
|-- models/
|   `-- cannon/
|       |-- CMakeLists.txt
|       |-- include/
|       |   |-- cannon.h
|       |   `-- cannon_analytic.h
|       `-- src/
|           |-- cannon_init.c
|           |-- cannon_analytic.c
|           `-- cannon_shutdown.c
|-- RUN_test/
|   `-- input.py
|-- build/                      Generated build products
`-- DP_Product/                 Generated Trick diagnostic products
```

### Top-level CMake configuration

[CMakeLists.txt](./CMakeLists.txt) sets the language requirements, locates Trick through the project's custom module, adds the cannon library, and creates the executable:

```cmake
find_package(Trick 25 REQUIRED)
add_subdirectory(models/cannon)

trick_add_simulation(S_main
    S_DEFINE S_define
    MODELS cannon)
```

`Trick::Trick` is the dependency target carrying Trick's include paths, compile definitions, static archives, and third-party link dependencies. It is defined by this project, not an upstream installed CMake package.

[CMakePresets.json](./CMakePresets.json) stores the default build directory, build type, and Trick location. CMake also exports `build/compile_commands.json` for editor tooling.

### Simulation definition and scheduling

[S_define](./S_define) describes how the model connects to Trick. It includes Trick's standard system simulation object and declares a `CannonSimObject` containing one `CANNON` state object. The global instance is named `dyn`, which is why Python accesses the state through `dyn.cannon`.

Its job declarations define the model lifecycle:

| Job | Function | Responsibility |
|---|---|---|
| Default data | `cannon_default_data` | Set launch conditions, acceleration, time, and impact flags. |
| Initialization | `cannon_init` | Convert launch speed and angle into velocity components and initialize state. |
| Scheduled, every 0.01 s | `cannon_analytic` | Calculate trajectory state and handle impact. |
| Shutdown | `cannon_shutdown` | Print the final state using Trick's executive time. |

The parenthesized job declarations and `##include` are **Trick configuration syntax**, not ordinary C++. Trick's configuration processor translates them into compilable C++ and job registration code. The `LIBRARY DEPENDENCIES` block identifies model source dependencies for Trick's processing; the CMake model target separately lists what CMake compiles.

### Cannon state and physics

[cannon.h](./models/cannon/include/cannon.h) defines the `CANNON` structure and the default-data, initialization, and shutdown function declarations. It stores initial and current position and velocity, acceleration, launch settings, model time, and impact information. Array index 0 is horizontal (`x`); index 1 is vertical (`y`).

The comments beside structure members are also input to Trick's introspection tools: they describe units and optional input/output attributes. For example, `*i` marks an input-only field. The `extern "C"` guards let generated C++ code call the C model functions.

[cannon_analytic.h](./models/cannon/include/cannon_analytic.h) includes the state definition and declares the scheduled trajectory function.

[cannon_init.c](./models/cannon/src/cannon_init.c) implements both default-data and initialization jobs. Defaults are set first; the Python input script can override them before initialization derives the velocity components.

[cannon_analytic.c](./models/cannon/src/cannon_analytic.c) evaluates the constant-acceleration equations independently in each axis:

```text
velocity(t) = initial_velocity + acceleration * t
position(t) = initial_position + initial_velocity * t + 0.5 * acceleration * t²
```

This is an analytic model, not a numerical integration example. When a scheduled evaluation finds the ball below ground, it solves for the exact impact time, calculates the corresponding horizontal position, clamps height to zero, and sets velocity to zero. It prints the impact message once.

The model advances its own time by a hard-coded **0.01 s** each call. If the scheduling interval changes in [S_define](./S_define), the `time_step` in this source must change to match.

[cannon_shutdown.c](./models/cannon/src/cannon_shutdown.c) reports the final position and velocity and obtains shutdown time from Trick through `exec_get_sim_time()`.

[models/cannon/CMakeLists.txt](./models/cannon/CMakeLists.txt) compiles these three sources into the static `cannon` library. Its public include directory lets both generated code and Trick's tools resolve headers such as `cannon/include/cannon_analytic.h`.

### CMake-to-Trick bridge

[FindTrick.cmake](./cmake/FindTrick.cmake) provides two pieces:

1. **Dependency discovery:** locate the built Trick tree, read its version and `config_user.mk`, choose its Python interpreter, find supporting libraries, and construct `Trick::Trick`. Trick archives are linked using whole-archive semantics, retaining objects needed by the framework.
2. **Simulation generation:** implement `trick_add_simulation`. It stages a copy of the simulation definition in `build/S_main_trick/`, obtains the makefile template embedded in `trick-CP`, and asks GNU Make only for generated sources and the Python support archive.

Generation happens during **CMake configuration**. Trick's configuration processor, Interface Code Generator (ICG), and SWIG generate the simulation glue, model metadata, and Python bindings. CMake then reads Trick's generated link lists to identify generated C++ sources and compiles and links them alongside the cannon library.

This means the project uses CMake for compilation and linking, but **does not eliminate Trick's generator tools or its Make-based generation rules**. It adapts them instead of reimplementing them.

The module registers the simulation definition and processed model headers as CMake configuration dependencies. Editing those files causes a subsequent build to reconfigure and rerun generation. Ordinary model implementation changes are handled by CMake's compiler dependency tracking.

Generation diagnostics are saved in `build/S_main_trick/codegen.log`. Generated files should not be edited by hand.

### Runtime support

[trick_runtime_env.cpp](./cmake/trick_runtime_env.cpp) initializes the environment expected by Trick before simulation startup:

- Supplies the configured `TRICK_HOME` if it is not already set.
- Supplies an empty `TRICK_PYTHON_PATH` if it is not already set.
- Prepends the generated `trick.zip` and its internal `trick` directory to `PYTHONPATH`, preserving existing entries afterward.

This accommodates Trick's working-directory assumptions without requiring a shell wrapper. The build copies the simulation's generated Python support archive beside the executable as `build/trick.zip`.

The executable is **not a standalone relocatable distribution**: the Trick location and Python archive location are compiled in, and external shared libraries are still required. Running from a different working directory works; moving the build or Trick checkout requires reconfiguration and rebuilding.

### Run configuration and generated products

[RUN_test/input.py](./RUN_test/input.py) is the user-editable run configuration. Despite the directory name, it is currently an example run, not an automated test suite.

Trick may write files such as `S_job_execution`, `S_run_summary`, `_init_log.csv`, `send_hs`, and `varserver_log` into the run directory. It can also create a `DP_Product/` directory relative to the working directory for diagnostic products. These are generated outputs, not model source files. The example does not explicitly configure a trajectory data-recording group or plotting application.

[S_overrides.mk](./S_overrides.mk) retains the tutorial's model include-path settings for the classic Trick build workflow. The CMake bridge supplies its own include paths to generation and does not read this file from the project root.

## Current scope

This is a small, macOS-validated learning example, not a general-purpose replacement for Trick's build system. The bridge assumes a built Trick source tree with its existing static-library layout and generator templates. Other platforms, optional Trick configurations, installation, and relocatable packaging have not been validated.