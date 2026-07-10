#  InverseTwoPunctures

Find the ADM momenta for a given set of BH spins, separation, mass ratio and ADM mass.

Starting from an initial guess of the ADM momenta, the TwoPunctures code is run iteratively, correcting the ADM momenta for each run until a tolerance is met.
To speed up this process, we start with low quality settings until a weaker tolerance is met, and then we transition to production settings to determine the final answer.
