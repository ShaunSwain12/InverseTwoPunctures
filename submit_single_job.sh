#!/bin/bash

#! Name of the job:
#SBATCH --job-name TwoPunctures
#! How many whole nodes should be allocated?
#SBATCH --nodes=1
#! How many tasks per node
#SBATCH --ntasks=1
#! How many cores per task
#! The solver is OpenMP-only; raise this for a parallel solve (it sets
#! OMP_NUM_THREADS below). Keep --ntasks=1 (it is not an MPI program).
#SBATCH --cpus-per-task=1
#! How much wallclock time will be required?
#SBATCH --time=04:00:00
#! Never send job email. submit.sh also passes --mail-type=NONE on the sbatch
#! command line; set it here too so running this script directly behaves the
#! same.
#SBATCH --mail-type=NONE
#! Merge stderr into the stdout log (slurm-%j.out): the standalone prints its
#! ADM-mass line to stderr, and the tuning driver greps the .out file for it.
#! twopunctures-standalone prints no completion marker, and this cluster has
#! no Slurm accounting DB (sacct), so this script writes its own exit code to
#! ./exit_code for the driver to check instead.

# Parfile-driven build (this repo's Main.cc + Makefile, linked against the
# pristine twopunctures-standalone library); a single shared-memory (OpenMP)
# program taking the parameter file as argv[1], so it is run directly rather
# than via mpirun.
application=./twopunctures
options=./params.par

export OMP_NUM_THREADS=$SLURM_CPUS_PER_TASK
export OMP_PROC_BIND=false

cd "$SLURM_SUBMIT_DIR"
echo -e "Changed directory to `pwd`.\n"

echo -e "JobID: $SLURM_JOB_ID\n======"
echo "Time: `date`"
echo "Running on master node: `hostname`"
echo "Current directory: `pwd`"
echo -e "\nnodes=$SLURM_JOB_NUM_NODES  cpus-per-task=$SLURM_CPUS_PER_TASK  OMP_NUM_THREADS=$OMP_NUM_THREADS"

echo -e "\nExecuting command:\n==================\n$application $options\n"

$application $options
rc=$?
echo -e "\nExit code: $rc"
echo "$rc" > exit_code
exit $rc


