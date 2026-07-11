#  InverseTwoPunctures

Find the ADM momenta for a given set of BH spins, separation, mass ratio and ADM mass.

Starting from an initial guess of the ADM momenta, the TwoPunctures code is run iteratively, correcting the ADM momenta for each run until a tolerance is met.
To speed up this process, we start with low quality settings until a weaker tolerance is met, and then we transition to production settings to determine the final answer.

## How it solves

The upstream [`twopunctures-standalone`](https://bitbucket.org/relastro/twopunctures-standalone/src/master/)
solver (a Cactus-free copy of the Einstein Toolkit TwoPunctures thorn) is a
library (`libtwopunctures.a`) plus a demo `cpp-standalone/Main.cc` that
**hardcodes every parameter and ignores its command-line argument** — there is
no parameter-file parser upstream. [`Main.cc`](Main.cc) in *this* repo is a
small, separate driver that links against that pristine, unmodified library
and adds a real `key = value` parser, so the momentum can actually be varied
between iterations. It does not touch or fork the upstream clone.

## Dependencies

| Dependency | Purpose | macOS | Linux / HPC |
| --- | --- | --- | --- |
| C++ compiler | build the solver | Apple `clang` (the default `g++`) | `g++` (GCC) |
| GNU Make | build the solver | `make` (Xcode CLT) | `make` |
| **GSL** (GNU Scientific Library) | required by the solver | `brew install gsl` | system package (`libgsl-dev`) or `module load gsl` |
| **OpenMP** *(optional, for a parallel solve)* | speeds up the solve | `brew install libomp` | built into GCC (`-fopenmp`) |
| Bash | run the driver `submit.sh` | 3.2 (system) is enough | any |
| Slurm (`sbatch`, `squeue`, `scancel`) | only for `--mode slurm` | — | provided by the cluster |
| `mail` | email notifications (on by default; see [Running](#running)) | optional | optional |

Notes:

* **`mpirun` is not needed.** The solver is a single shared-memory (OpenMP)
  process; set the thread count with `OMP_NUM_THREADS`.
* The GSL shared libraries must also be found at **run time** (on HPC, keep the
  same `module load gsl` in your job environment).

## Building the solver

```sh
./install_deps.sh
```

On macOS this installs GSL/OpenMP via Homebrew (prompting to install the
Xcode Command Line Tools first if needed) and checks for a compiler and
`make`. On Linux it only *checks* for these (HPC clusters normally provide
them system-wide or via `module load`, and login nodes usually have no
`sudo`) — if something's missing and `apt-get`+`sudo` are both available it
offers to install them, otherwise it tells you what's missing so you can ask
your sysadmin / load the right module. Either way, it then clones
[`twopunctures-standalone`](https://bitbucket.org/relastro/twopunctures-standalone/src/master/)
into a sibling directory (if not already present somewhere) and builds
`./twopunctures`. Safe to re-run any time — every step is a no-op if already
satisfied. See `./install_deps.sh --help` for options (`--tp-dir`,
`--no-clone`, `--no-build`).

To build by hand instead:

```sh
make            # builds ./twopunctures from Main.cc, linked against
                # $TP_STANDALONE_DIR/libtwopunctures/libtwopunctures.a
                # (built automatically if missing)
```

`TP_STANDALONE_DIR` defaults to a sibling directory of this repo
(`../twopunctures-standalone`); override it if your clone lives elsewhere:

```sh
make TP_STANDALONE_DIR=<path-to-twopunctures-standalone>
```

The Makefile never builds, cleans, or otherwise modifies anything under
`TP_STANDALONE_DIR` beyond invoking its own Makefile to produce the `.a` if
needed.

## Running

The driver is [`submit.sh`](submit.sh). It takes an initial parameter file and a
target total ADM mass, scales the momentum magnitude, and root-finds until the
reported ADM mass matches the target (coarse resolution first, then production).

```sh
# Local: run the solver directly in this process, in the foreground.
./submit.sh --mode local params.par 1.0

# Slurm: each iteration is submitted with sbatch submit_single_job.sh; the
# driver auto-detaches into the background and polls squeue between runs, so
# it's safe to log out once it's started.
./submit.sh --mode slurm params.par 1.0
```

Run `./submit.sh --help` for the full option list (tolerances, resolutions,
max iterations, `--dry-run`, ...). A few things worth knowing:

* **Email notifications are on by default**, sent to the account running the
  script: one when the campaign starts, one when it ends (converged,
  exhausted `--max-iter`, or errored). Pass `--mail-user someone@example.com`
  to redirect them, or `--mail-user ""` to disable. Per-iteration Slurm jobs
  never send mail themselves (`--mail-type=NONE`), so you only ever get the
  two campaign-level emails, not one per iteration.
* **Slurm mode auto-backgrounds itself** (`setsid` + `nohup`) so a plain
  invocation survives logout; pass `--foreground` to stay attached instead
  (e.g. inside `tmux`). **Local mode always stays attached** — it's running
  the solve itself, right here.
* This cluster has no Slurm accounting DB (`sacct` is disabled), so success
  is detected via an `exit_code` file [`submit_single_job.sh`](submit_single_job.sh)
  writes after each run, not by grepping solver output for a completion
  marker (the solver doesn't print one).
* In **slurm mode** the driver symlinks the built `twopunctures` binary and
  `submit_single_job.sh` into each per-iteration directory and submits the
  job. For a parallel solve on the cluster, raise `--cpus-per-task` in
  `submit_single_job.sh` (it exports `OMP_NUM_THREADS=$SLURM_CPUS_PER_TASK`).
* In **local mode** it runs `./twopunctures` directly; set `OMP_NUM_THREADS`
  yourself to control threading.
* All progress (both modes) is appended to `<workdir>/progress.log`
  (`tail -f` it); the converged parameter file is written to
  `<workdir>/final_params.par`.

## Parameter file

[`params.par`](params.par) uses the solver's native parameter names (the
fields of `TP::Parameters` in
[`libtwopunctures/TP_Parameters.h`](https://bitbucket.org/relastro/twopunctures-standalone/src/master/libtwopunctures/TP_Parameters.h)),
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

See [`Main.cc`](Main.cc)'s `read_params_file()` for the complete, authoritative
list of recognized keys; an unrecognized key prints a warning and is ignored
rather than failing the run.
