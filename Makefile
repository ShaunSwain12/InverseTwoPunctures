# Builds ./twopunctures from Main.cc, linked against the pristine,
# unmodified twopunctures-standalone clone's static library and headers.
# Never builds, cleans, or otherwise touches anything under
# TP_STANDALONE_DIR beyond invoking its own Makefile (with OMP overridden
# from the command line, not by editing that Makefile) to produce the .a
# if it's missing.

TP_STANDALONE_DIR ?= /scratch/sswain/twopunctures-standalone
LIB := $(TP_STANDALONE_DIR)/libtwopunctures/libtwopunctures.a
INC := -I$(TP_STANDALONE_DIR)/libtwopunctures

CXX ?= g++
LIBS := -lgsl -lgslcblas -lm

binary := twopunctures

# OpenMP flags. On Linux/GCC, plain -fopenmp works. On macOS, CXX=g++ is
# really Apple clang, which rejects -fopenmp outright; if Homebrew's libomp
# is installed, use clang's -Xpreprocessor incantation instead, otherwise
# fall back to a serial build (correctness is unaffected, just slower).
# Override any of this explicitly with `make OMP=...`.
UNAME_S := $(shell uname -s)
ifeq ($(UNAME_S),Darwin)
    LIBOMP_PREFIX := $(shell brew --prefix libomp 2>/dev/null)
    ifneq ($(LIBOMP_PREFIX),)
        OMP ?= -Xpreprocessor -fopenmp -I$(LIBOMP_PREFIX)/include
        OMP_LIBS := -L$(LIBOMP_PREFIX)/lib -lomp
    else
        OMP ?=
        OMP_LIBS :=
        $(warning libomp not found (brew install libomp); building $(binary) without OpenMP, serial only)
    endif
else
    OMP ?= -fopenmp
    OMP_LIBS :=
endif

CXXFLAGS := -std=c++11 -O2 $(OMP)
LDFLAGS := $(OMP)

.PHONY: all clean

all: $(binary)

$(LIB):
	$(MAKE) -C $(TP_STANDALONE_DIR)/libtwopunctures OMP="$(OMP)"

Main.o: Main.cc
	$(CXX) $(CXXFLAGS) $(INC) -c Main.cc -o Main.o

$(binary): Main.o $(LIB)
	$(CXX) $(LDFLAGS) -o $(binary) Main.o $(LIB) $(OMP_LIBS) $(LIBS)

clean:
	rm -f Main.o $(binary)
