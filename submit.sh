#!/usr/bin/env bash
#
# tune_adm_mass.sh — drive TwoPunctures to a target *total* ADM mass by
# tuning the momentum magnitude, ramping resolution up as the answer
# converges.
#
# TwoPunctures takes bare/target puncture masses + momenta + spins and
# reports the total system ADM mass ("TP: The total ADM mass is ...").
# This script inverts that: given a target total ADM mass, it scales the
# momentum vectors (par_P_plus/minus, direction fixed, magnitude
# free) by a common factor alpha and root-finds on alpha via the secant
# method until the reported ADM mass matches the target. Runs start at a
# coarse (fast) spectral resolution and switch permanently to production
# resolution once the residual drops below --coarse-tol; convergence is
# only declared for a run actually performed at production resolution.
#
# Usage:
#   ./tune_adm_mass.sh [options] <initial_params.txt> <target_adm_mass>
#
# Run with --help for the full option list.

set -euo pipefail

ORIG_ARGS=("$@")
SCRIPT_PATH=$(realpath "$0")

# ---------------------------------------------------------------------------
# Defaults
# ---------------------------------------------------------------------------
MODE=slurm                # slurm | local
FINAL_TOL=1e-8
COARSE_TOL=1e-3
INITIAL_STEP=0.05          # fractional momentum bump used for the very first
                            # correction (no secant history yet)
MAX_ITER=40
POLL_INTERVAL=15           # seconds, slurm mode only
MAX_STEP_FACTOR=3.0        # clamp |alpha_new/alpha| into [1/F, F] each step
COARSE_NPOINTS="24 24 16"
COARSE_NEWTON_TOL=1e-10
COARSE_ADM_TOL=1e-10
PROD_NPOINTS="64 64 48"
PROD_NEWTON_TOL=1e-12
PROD_ADM_TOL=1e-12
EXE="<path-to-TwoPunctures-executable>"  # must be set by user
SUBMIT_SCRIPT="./submit_single_job.sh"
WORKDIR="./output"
DRY_RUN=0
FOREGROUND=0
MAIL_USER=""

usage() {
    cat <<EOF
Usage: $0 [options] <initial_params.txt> <target_adm_mass>

Options:
  --mode {slurm|local}       Job submission method (default: $MODE).
                              slurm  -> each run is submitted via
                                        sbatch $SUBMIT_SCRIPT (compute nodes);
                                        this orchestrator auto-backgrounds
                                        itself (see below) and just polls
                                        squeue between submissions.
                              local  -> run the executable directly with
                                        mpirun, in this process, in the
                                        foreground. Never backgrounds itself.
  --final-tol TOL             Convergence tolerance on the ADM mass residual,
                               checked only for production-resolution runs
                               (default: $FINAL_TOL).
  --coarse-tol TOL             |residual| threshold below which the script
                               permanently switches to production resolution
                               (default: $COARSE_TOL).
  --initial-step FRAC          Fractional momentum bump for the first
                               correction, before secant has two points
                               (default: $INITIAL_STEP).
  --max-iter N                  Maximum number of TwoPunctures runs (default: $MAX_ITER).
  --poll-interval SEC            Seconds between squeue polls in slurm mode (default: $POLL_INTERVAL).
  --coarse-npoints "A B phi"     Spectral resolution while searching (default: "$COARSE_NPOINTS").
  --coarse-newton-tol TOL        Newton_tol at coarse resolution (default: $COARSE_NEWTON_TOL).
  --coarse-adm-tol TOL           adm_tol at coarse resolution (default: $COARSE_ADM_TOL).
  --prod-npoints "A B phi"       Production spectral resolution (default: "$PROD_NPOINTS").
  --prod-newton-tol TOL          Newton_tol at production resolution (default: $PROD_NEWTON_TOL).
  --prod-adm-tol TOL             adm_tol at production resolution (default: $PROD_ADM_TOL).
  --exe PATH                     TwoPunctures executable (default: $EXE).
  --submit-script PATH           sbatch script template, slurm mode only (default: $SUBMIT_SCRIPT).
  --workdir DIR                  Directory to hold per-iteration runs
                                 (default: tune_<param-file-stem>_<timestamp>).
  --dry-run                      Print the iter_000 parameters that would be
                                 generated and exit without running anything.
  --foreground                   slurm mode only: stay attached to this
                                 terminal instead of auto-backgrounding (see
                                 below). No effect in local mode, which is
                                 always attached. Implied by --dry-run.
  --mail-user ADDRESS            Send exactly two notification emails: one
                                 when the campaign starts (before the first
                                 run is submitted) and one when it ends
                                 (converged, exhausted --max-iter, or
                                 errored). Omit to send no email at all.
                                 Per-iteration sbatch jobs are always
                                 submitted with --mail-type=NONE regardless
                                 of this setting, overriding submit.sh's own
                                 --mail-type=all, so you never get one email
                                 per iteration.
  -h, --help                     Show this help.

In slurm mode, by default the script detaches itself into the background
(setsid + nohup) on startup and prints its PID and log file, so a plain
invocation survives you logging out; the actual TwoPunctures runs happen on
compute nodes via sbatch regardless. Pass --foreground to stay attached
instead (e.g. if you are already inside tmux/screen). In local mode the
script always stays attached, since it runs the solver itself right here.
Either way, all progress is appended to <workdir>/progress.log (tail -f it).

The initial parameter file's par_P_plus/par_P_minus vectors (single-line
"x y z" form) define the fixed momentum *direction*; only their common
magnitude is tuned. They must not both be exactly zero.
EOF
}

# ---------------------------------------------------------------------------
# Arg parsing
# ---------------------------------------------------------------------------
POSITIONAL=()
while [[ $# -gt 0 ]]; do
    case "$1" in
        --mode) MODE=$2; shift 2 ;;
        --final-tol) FINAL_TOL=$2; shift 2 ;;
        --coarse-tol) COARSE_TOL=$2; shift 2 ;;
        --initial-step) INITIAL_STEP=$2; shift 2 ;;
        --max-iter) MAX_ITER=$2; shift 2 ;;
        --poll-interval) POLL_INTERVAL=$2; shift 2 ;;
        --coarse-npoints) COARSE_NPOINTS=$2; shift 2 ;;
        --coarse-newton-tol) COARSE_NEWTON_TOL=$2; shift 2 ;;
        --coarse-adm-tol) COARSE_ADM_TOL=$2; shift 2 ;;
        --prod-npoints) PROD_NPOINTS=$2; shift 2 ;;
        --prod-newton-tol) PROD_NEWTON_TOL=$2; shift 2 ;;
        --prod-adm-tol) PROD_ADM_TOL=$2; shift 2 ;;
        --exe) EXE=$2; shift 2 ;;
        --submit-script) SUBMIT_SCRIPT=$2; shift 2 ;;
        --workdir) WORKDIR=$2; shift 2 ;;
        --dry-run) DRY_RUN=1; shift ;;
        --foreground) FOREGROUND=1; shift ;;
        --mail-user) MAIL_USER=$2; shift 2 ;;
        -h|--help) usage; exit 0 ;;
        --) shift; POSITIONAL+=("$@"); break ;;
        -*) echo "Unknown option: $1" >&2; usage; exit 1 ;;
        *) POSITIONAL+=("$1"); shift ;;
    esac
done

if [[ ${#POSITIONAL[@]} -ne 2 ]]; then
    usage
    exit 1
fi
PARAM_FILE=${POSITIONAL[0]}
TARGET_MASS=${POSITIONAL[1]}

[[ -f "$PARAM_FILE" ]] || { echo "ERROR: param file '$PARAM_FILE' not found" >&2; exit 1; }
[[ "$MODE" == slurm || "$MODE" == local ]] || { echo "ERROR: --mode must be slurm or local" >&2; exit 1; }
read -r _ _ COARSE_PHI <<< "$COARSE_NPOINTS"
read -r _ _ PROD_PHI <<< "$PROD_NPOINTS"
for phi in "$COARSE_PHI" "$PROD_PHI"; do
    if (( phi % 4 != 0 )); then
        echo "ERROR: npoints_phi ($phi) must be a multiple of 4" >&2
        exit 1
    fi
done

if [[ -z "$WORKDIR" ]]; then
    stem=$(basename "$PARAM_FILE")
    stem=${stem%.*}
    WORKDIR="tune_${stem}_$(date +%Y%m%d_%H%M%S)"
fi

# ---------------------------------------------------------------------------
# Auto-detach (slurm mode only): re-exec ourselves as a setsid+nohup
# background process so a run started interactively survives logout. The
# actual compute always happens on compute nodes via sbatch regardless, so
# this orchestrator is cheap to leave running (periodic squeue polls).
# The re-exec'd child (TP_TUNE_DAEMONIZED=1) falls through this block
# untouched, since its stdout/stderr are already pointed at progress.log by
# the redirect below. --foreground/--dry-run opt out and stay attached.
#
# local mode never detaches: it runs the solver directly in this process,
# so "run the script" already means "run it here, now" with nothing to poll.
# ---------------------------------------------------------------------------
mkdir -p "$WORKDIR"
LOGFILE="$WORKDIR/progress.log"

if [[ "$DRY_RUN" != 1 && "$MODE" == slurm && "$FOREGROUND" != 1 && -z "${TP_TUNE_DAEMONIZED:-}" ]]; then
    # setsid fully detaches from the controlling terminal, but it is Linux-only.
    # On macOS (no setsid) fall back to plain nohup: combined with the disown
    # below it still backgrounds the run and shields it from SIGHUP on logout.
    # Re-exec through bash explicitly so this does not depend on the script's
    # execute bit being set (which may be lost across copies/checkouts).
    if command -v setsid >/dev/null 2>&1; then
        TP_TUNE_DAEMONIZED=1 setsid nohup bash "$SCRIPT_PATH" "${ORIG_ARGS[@]}" --workdir "$WORKDIR" \
            > "$LOGFILE" 2>&1 < /dev/null &
    else
        TP_TUNE_DAEMONIZED=1 nohup bash "$SCRIPT_PATH" "${ORIG_ARGS[@]}" --workdir "$WORKDIR" \
            > "$LOGFILE" 2>&1 < /dev/null &
    fi
    echo $! > "$WORKDIR/pid"
    # Print the detach summary both to the terminal and to a file, so the PID
    # and the tail/check commands are recorded once the terminal is gone.
    {
        echo "Detached into the background (PID $(cat "$WORKDIR/pid")); safe to log out now."
        echo "Progress log       : $LOGFILE"
        echo "Tail it with       : tail -f $LOGFILE"
        echo "Check it's running : ps -p \$(cat $WORKDIR/pid)"
    } | tee "$WORKDIR/terminal_output.txt"
    disown
    exit 0
elif [[ "$DRY_RUN" != 1 && -z "${TP_TUNE_DAEMONIZED:-}" ]]; then
    # Foreground path: local mode always, or slurm mode with --foreground.
    # Still tee to progress.log so both modes leave the same kind of record.
    exec > >(tee -a "$LOGFILE") 2>&1
fi

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

# get_param FILE KEY -> value (trimmed, last match wins)
get_param() {
    grep -E "^[[:space:]]*$2[[:space:]]*=" "$1" | tail -1 \
        | sed -E "s/^[^=]*=[[:space:]]*//; s/[[:space:]]+\$//"
}

# set_param FILE KEY VALUE -> replace first matching line in place, or append
set_param() {
    local file=$1 key=$2 value=$3
    if grep -qE "^[[:space:]]*$key[[:space:]]*=" "$file"; then
        awk -v k="$key" -v v="$value" '
            BEGIN{done=0}
            {
                if (!done && $0 ~ "^[ \t]*" k "[ \t]*=") { print k " = " v; done=1 }
                else print
            }' "$file" > "$file.tmp"
        mv "$file.tmp" "$file"
    else
        printf "%s = %s\n" "$key" "$value" >> "$file"
    fi
}

# scale_vector "x y z" factor -> "x*f y*f z*f"
scale_vector() {
    awk -v f="$2" -v vec="$1" 'BEGIN{
        n = split(vec, a, /[ \t]+/);
        out = "";
        for (i = 1; i <= n; i++) {
            out = out sprintf("%.15e", a[i] * f);
            if (i < n) out = out " ";
        }
        print out;
    }'
}

vector_magnitude() {
    awk -v vec="$1" 'BEGIN{
        n = split(vec, a, /[ \t]+/);
        s = 0;
        for (i = 1; i <= n; i++) s += a[i] * a[i];
        print sqrt(s);
    }'
}

abs_val() { awk -v x="$1" 'BEGIN{print (x < 0) ? -x : x}'; }

# send_mail SUBJECT BODY -> one notification, skipped for dry-run or if
# --mail-user was not given
MAIL_FROM="TwoPunctures ID Solver <$(whoami)@$(hostname -f 2>/dev/null || hostname)>"

send_mail() {
    local subject=$1 body=$2
    [[ "$DRY_RUN" != 1 && -n "$MAIL_USER" ]] || return 0
    printf '%s\n' "$body" | mail -a "From: $MAIL_FROM" -s "$subject" "$MAIL_USER" \
        || echo "WARNING: failed to send notification email to $MAIL_USER" >&2
}

# ---------------------------------------------------------------------------
# Set up
# ---------------------------------------------------------------------------
mkdir -p "$WORKDIR"
BASE_PARAMS="$WORKDIR/base_params.txt"
cp "$PARAM_FILE" "$BASE_PARAMS"

P0_PLUS=$(get_param "$BASE_PARAMS" par_P_plus)
P0_MINUS=$(get_param "$BASE_PARAMS" par_P_minus)
[[ -n "$P0_PLUS" && -n "$P0_MINUS" ]] || {
    echo "ERROR: could not read par_P_plus/par_P_minus from $PARAM_FILE" >&2
    echo "       (expected single-line vector form, e.g. 'par_P_plus = 0.0 -0.1 0.0')" >&2
    exit 1
}

MAG_PLUS=$(vector_magnitude "$P0_PLUS")
MAG_MINUS=$(vector_magnitude "$P0_MINUS")
if awk -v a="$MAG_PLUS" -v b="$MAG_MINUS" 'BEGIN{exit !(a<1e-14 && b<1e-14)}'; then
    echo "ERROR: initial momenta are both (numerically) zero." >&2
    echo "       This script scales the momentum magnitude and needs a nonzero" >&2
    echo "       initial direction to scale (e.g. an estimate from PN formulae)." >&2
    exit 1
fi

echo "Working directory : $WORKDIR"
echo "Initial P_plus     : $P0_PLUS"
echo "Initial P_minus    : $P0_MINUS"
echo "Target ADM mass    : $TARGET_MASS"
echo "Mode               : $MODE"
echo

jobid=""
converged=0

# on_exit runs exactly once no matter how the script terminates (normal
# completion, --max-iter exhausted, a hard error inside run_iteration, or a
# signal via on_signal below) so exactly one "campaign finished" email goes
# out, however things ended.
on_exit() {
    local code=$?
    if [[ "$MODE" == slurm && -n "$jobid" ]]; then
        scancel "$jobid" 2>/dev/null || true
    fi

    local status_line
    if [[ "$converged" == 1 ]]; then
        status_line="Converged after $((iter + 1)) run(s). ADM mass=${MASS:-N/A} target=$TARGET_MASS residual=${RESIDUAL:-N/A}"
    elif [[ $code -eq 2 ]]; then
        status_line="Did NOT converge within $MAX_ITER iterations. Last ADM mass=${MASS:-N/A} residual=${RESIDUAL:-N/A}"
    else
        status_line="Stopped with an error (exit code $code). Check $WORKDIR/progress.log"
    fi

    send_mail "TwoPunctures ADM tuning finished ($WORKDIR) - exit $code" \
"$status_line
Working directory: $(realpath "$WORKDIR" 2>/dev/null || echo "$WORKDIR")
Host: $(hostname)
Time: $(date)"
}
on_signal() {
    echo "Received SIG$1, cancelling and exiting..." >&2
    exit 1
}
trap on_exit EXIT
trap 'on_signal INT' INT
trap 'on_signal TERM' TERM

send_mail "TwoPunctures ADM tuning started ($WORKDIR)" \
"Started tuning $PARAM_FILE toward target ADM mass $TARGET_MASS
Mode: $MODE
Working directory: $(realpath "$WORKDIR")
Host: $(hostname)
Time: $(date)"

# ---------------------------------------------------------------------------
# Iteration: build one param file for the given alpha/tier and run it
# Sets globals: MASS, RESIDUAL, ABSRES
# ---------------------------------------------------------------------------
run_iteration() {
    local iter=$1 alpha=$2 production=$3
    local iterdir="$WORKDIR/iter_$(printf '%03d' "$iter")"
    mkdir -p "$iterdir"
    cp "$BASE_PARAMS" "$iterdir/params.par"

    local Pp Pm
    Pp=$(scale_vector "$P0_PLUS" "$alpha")
    Pm=$(scale_vector "$P0_MINUS" "$alpha")
    set_param "$iterdir/params.par" par_P_plus "$Pp"
    set_param "$iterdir/params.par" par_P_minus "$Pm"

    local npts newton_tol adm_tol npA npB npphi
    if [[ "$production" == 1 ]]; then
        npts=$PROD_NPOINTS; newton_tol=$PROD_NEWTON_TOL; adm_tol=$PROD_ADM_TOL
    else
        npts=$COARSE_NPOINTS; newton_tol=$COARSE_NEWTON_TOL; adm_tol=$COARSE_ADM_TOL
    fi
    read -r npA npB npphi <<< "$npts"
    set_param "$iterdir/params.par" npoints_A "$npA"
    set_param "$iterdir/params.par" npoints_B "$npB"
    set_param "$iterdir/params.par" npoints_phi "$npphi"
    set_param "$iterdir/params.par" Newton_tol "$newton_tol"
    set_param "$iterdir/params.par" adm_tol "$adm_tol"

    local tier_name="coarse"; [[ "$production" == 1 ]] && tier_name="production"
    echo "[iter $iter] alpha=$alpha  tier=$tier_name  npoints=($npA $npB $npphi)"

    if [[ "$DRY_RUN" == 1 ]]; then
        echo "--dry-run: generated $iterdir/params.par, stopping before execution."
        echo "----------------------------------------------------------------"
        cat "$iterdir/params.par"
        exit 0
    fi

    local outfile
    if [[ "$MODE" == local ]]; then
        outfile="$iterdir/run.log"
        ln -sf "$(realpath "$EXE")" "$iterdir/$(basename "$EXE")"
        # standalone is a single OpenMP process taking the parfile as argv[1]
        (cd "$iterdir" && "./$(basename "$EXE")" ./params.par) > "$outfile" 2>&1 || {
            echo "ERROR: TwoPunctures run failed, see $outfile" >&2
            exit 1
        }
    else
        ln -sf "$(realpath "$EXE")" "$iterdir/$(basename "$EXE")"
        ln -sf "$(realpath "$SUBMIT_SCRIPT")" "$iterdir/submit.sh"
        local submit_out
        submit_out=$(cd "$iterdir" && sbatch --mail-type=NONE submit.sh)
        jobid=$(echo "$submit_out" | grep -oE '[0-9]+$')
        [[ -n "$jobid" ]] || { echo "ERROR: could not parse job id from: $submit_out" >&2; exit 1; }
        echo "[iter $iter] submitted job $jobid, waiting..."

        sleep 2
        while [[ -n "$(squeue -h -j "$jobid" 2>/dev/null)" ]]; do
            sleep "$POLL_INTERVAL"
        done
        jobid=""

        outfile="$iterdir/slurm-*.out"
        outfile=$(ls "$iterdir"/slurm-*.out 2>/dev/null | head -1 || true)
        [[ -n "$outfile" ]] || { echo "ERROR: no slurm output file found in $iterdir" >&2; exit 1; }
    fi

    grep -q "TwoPunctures finished." "$outfile" || {
        echo "ERROR: iter $iter did not finish successfully, see $outfile" >&2
        tail -30 "$outfile" >&2
        exit 1
    }

    MASS=$(grep "The total ADM mass is" "$outfile" | tail -1 | awk '{print $NF}')
    [[ -n "$MASS" ]] || { echo "ERROR: no ADM mass reported in $outfile" >&2; exit 1; }
    RESIDUAL=$(awk -v t="$TARGET_MASS" -v m="$MASS" 'BEGIN{print t-m}')
    ABSRES=$(abs_val "$RESIDUAL")
    echo "[iter $iter] ADM mass=$MASS  residual=$RESIDUAL"
}

# ---------------------------------------------------------------------------
# Main loop
# ---------------------------------------------------------------------------
alpha=1.0
alpha_prev=""
mass_prev=""
in_production=0

for ((iter = 0; iter < MAX_ITER; iter++)); do
    used_production=$in_production
    run_iteration "$iter" "$alpha" "$used_production"

    if [[ "$used_production" == 1 ]]; then
        if awk -v a="$ABSRES" -v tol="$FINAL_TOL" 'BEGIN{exit !(a<tol)}'; then
            echo
            echo "Converged at iteration $iter (production resolution)."
            echo "  ADM mass = $MASS   target = $TARGET_MASS   residual = $RESIDUAL"
            cp "$WORKDIR/iter_$(printf '%03d' "$iter")/params.par" "$WORKDIR/final_params.par"
            echo "Final parameter file: $WORKDIR/final_params.par"
            converged=1
            break
        fi
    else
        if awk -v a="$ABSRES" -v tol="$COARSE_TOL" 'BEGIN{exit !(a<tol)}'; then
            echo "[iter $iter] residual below coarse-tol ($COARSE_TOL); switching to production resolution"
            in_production=1
        fi
    fi

    # compute next alpha
    if [[ -z "$alpha_prev" ]]; then
        sign=$(awk -v r="$RESIDUAL" 'BEGIN{print (r>=0)?1:-1}')
        alpha_next=$(awk -v a="$alpha" -v s="$sign" -v st="$INITIAL_STEP" 'BEGIN{print a*(1+s*st)}')
    else
        denom=$(awk -v m1="$MASS" -v m0="$mass_prev" 'BEGIN{print m1-m0}')
        if awk -v d="$denom" 'BEGIN{d=(d<0)?-d:d; exit !(d<1e-14)}'; then
            sign=$(awk -v r="$RESIDUAL" 'BEGIN{print (r>=0)?1:-1}')
            alpha_next=$(awk -v a="$alpha" -v s="$sign" -v st="$INITIAL_STEP" 'BEGIN{print a*(1+s*st)}')
        else
            alpha_next=$(awk -v a1="$alpha" -v a0="$alpha_prev" -v m1="$MASS" -v m0="$mass_prev" -v t="$TARGET_MASS" \
                'BEGIN{print a1 - (m1-t)*(a1-a0)/(m1-m0)}')
        fi
        alpha_next=$(awk -v an="$alpha_next" -v a="$alpha" -v f="$MAX_STEP_FACTOR" 'BEGIN{
            lo=a/f; hi=a*f;
            if (an<lo) an=lo;
            if (an>hi) an=hi;
            print an;
        }')
    fi

    alpha_prev=$alpha
    mass_prev=$MASS
    alpha=$alpha_next
done

if [[ "$converged" != 1 ]]; then
    echo
    echo "WARNING: did not converge within $MAX_ITER iterations. Last residual: $RESIDUAL" >&2
    exit 2
fi
