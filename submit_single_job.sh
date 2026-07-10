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
#! What types of email messages do you wish to receive?
#SBATCH --mail-type=all
#! Merge stderr into the stdout log (slurm-%j.out): the standalone prints its
#! ADM-mass line and "TwoPunctures finished." marker to stderr, and the tuning
#! driver greps the .out file for them.

numnodes=$SLURM_JOB_NUM_NODES
mpi_tasks_per_node=$SLURM_NTASKS_PER_NODE
numtasks=$[${numnodes}*${mpi_tasks_per_node}]

# TwoPunctures-Standalone binary (built in cpp-standalone/); it is a single
# shared-memory (OpenMP) program and takes the parameter file as argv[1], so
# it is run directly rather than via mpirun.
application=./twopunctures
options=./params.par

workdir="$SLURM_SUBMIT_DIR"

export OMP_NUM_THREADS=$SLURM_CPUS_PER_TASK
export OMP_PROC_BIND=false

np=$[${numnodes}*${mpi_tasks_per_node}]

CMD="$application $options"

cd $workdir
echo -e "Changed directory to `pwd`.\n"

JOBID=$SLURM_JOB_ID

echo -e "JobID: $JOBID\n======"
echo "Time: `date`"
echo "Running on master node: `hostname`"
echo "Current directory: `pwd`"

#if [ "$SLURM_JOB_NODELIST" ]; then
#        #! Create a machine file:
#        export NODEFILE=`generate_pbs_nodefile`
#        cat $NODEFILE | uniq > machine.file.$JOBID
#        echo -e "\nNodes allocated:\n================"
#        echo `cat machine.file.$JOBID | sed -e 's/\..*$//g'`
#fi

echo -e "\nnumtasks=$numtasks, numnodes=$numnodes, mpi_tasks_per_node=$mpi_tasks_per_node (OMP_NUM_THREADS=$OMP_NUM_THREADS)"

echo -e "\nExecuting command:\n==================\n$CMD\n"

eval $CMD


