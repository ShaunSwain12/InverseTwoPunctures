#  InverseTwoPunctures

Find the ADM momenta for a given set of BH spins, separation, mass ratio and ADM mass.

Starting from an initial guess of the ADM momenta, the TwoPunctures code is run iteratively, correcting the ADM momenta for each run until a tolerance is met.
To speed up this process, we start with low quality settings until a weaker tolerance is met, and then we transition to production settings to determine the final answer.

## Dependencies

The workflow drives the [`twopunctures-standalone`](twopunctures-standalone/) solver
(a Cactus-free copy of the Einstein Toolkit TwoPunctures thorn) from a shell
script. You need:

| Dependency | Purpose | macOS | Linux / HPC |
| --- | --- | --- | --- |
| C++ compiler | build the solver | Apple `clang` (the default `g++`) | `g++` (GCC) |
| GNU Make | build the solver | `make` (Xcode CLT) | `make` |
| **GSL** (GNU Scientific Library) | required by the solver | `brew install gsl` | system package (`libgsl-dev`) or `module load gsl` |
| **OpenMP** *(optional, for a parallel solve)* | speeds up the solve | `brew install libomp` | built into GCC (`-fopenmp`) |
| Bash | run the driver `submit.sh` | 3.2 (system) is enough | any |
| Slurm (`sbatch`, `squeue`, `scancel`) | only for `--mode slurm` | — | provided by the cluster |
| `mail` | only for `--mail-user` email notifications | optional | optional |

Notes:

* **OpenMP is optional.** The solver only uses `#pragma omp` (no `omp.h`/`omp_*`
  calls), so without OpenMP it builds and runs correctly, just serially. On
  macOS the build auto-detects Homebrew `libomp`; if it is absent it falls back
  to a serial build. Force serial anywhere with `make OMP=`.
* **`mpirun` is not needed.** The standalone solver is a single shared-memory
  (OpenMP) process; set the thread count with `OMP_NUM_THREADS`.
* The GSL shared libraries must also be found at **run time** (on HPC, keep the
  same `module load gsl` in your job environment).

## Building the solver

```sh
cd twopunctures-standalone/cpp-standalone
make            # builds ../libtwopunctures/libtwopunctures.a and ./twopunctures
```

The Makefiles find GSL via `gsl-config` and pick a working OpenMP flag for the
platform automatically, so a plain `make` works on both macOS and Linux. Useful
overrides:

```sh
make OMP=                 # force a serial build (e.g. macOS without libomp)
make OMP=-fopenmp         # force GCC-style OpenMP
```

## Running

The driver is [`submit.sh`](submit.sh). It takes an initial parameter file and a
target total ADM mass, scales the momentum magnitude, and root-finds until the
reported ADM mass matches the target (coarse resolution first, then production).

```sh
# Local: run the solver directly in this process (foreground).
./submit.sh --mode local --exe twopunctures-standalone/cpp-standalone/twopunctures \
    params.par 1.0

# Slurm: each iteration is submitted with sbatch submit_single_job.sh; the
# driver auto-detaches and polls squeue between runs.
./submit.sh --mode slurm --exe ./twopunctures params.par 1.0
```

Run `./submit.sh --help` for the full option list (tolerances, resolutions,
max iterations, email notifications, `--dry-run`, ...).

* In **slurm mode** the driver symlinks the built `twopunctures` binary and
  [`submit_single_job.sh`](submit_single_job.sh) into each per-iteration
  directory and submits the job. For a parallel solve on the cluster, raise
  `--cpus-per-task` in `submit_single_job.sh` (it exports
  `OMP_NUM_THREADS=$SLURM_CPUS_PER_TASK`).
* In **local mode** it runs `./twopunctures` directly; set `OMP_NUM_THREADS`
  yourself to control threading.

## Parameter file

[`params.par`](params.par) uses the standalone solver's native parameter names
(the fields of `TP::Parameters` in
[`twopunctures-standalone/libtwopunctures/TP_Parameters.h`](twopunctures-standalone/libtwopunctures/TP_Parameters.h)),
one `name = value` per line, `#` for comments. Key parameters:

* `target_M_plus` / `target_M_minus` — target ADM masses (with
  `give_bare_mass = false`); or set `par_m_plus` / `par_m_minus` bare masses
  with `give_bare_mass = true`.
* `par_P_plus` / `par_P_minus` — linear momenta, single-line `x y z` vectors
  (these are what the driver scales).
* `par_S_plus` / `par_S_minus` — spins, `x y z`.
* `par_b` + `center_offset_x/y/z` — puncture placement: the `+` puncture sits at
  `x = center_offset_x + par_b`, the `-` puncture at `x = center_offset_x - par_b`
  (along `z` instead if `swap_xz = true`).
* `npoints_A/B/phi`, `Newton_tol`, `Newton_maxit`, `adm_tol` — spectral
  resolution and solver tolerances (`npoints_phi` must be a multiple of 4).
* `output_field_values` — set `false` to skip the demo field-value dump when you
  only need the ADM mass.
