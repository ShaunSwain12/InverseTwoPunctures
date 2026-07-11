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
binary := twopunctures

# GSL flags via gsl-config (ships with GSL itself, so this finds it wherever
# it's actually installed — Homebrew's lib/ dir in particular is often not
# on the default linker search path on macOS even when its include/ dir is,
# which is what a bare -lgsl runs into). Falls back to a bare link if
# gsl-config isn't on PATH at all.
GSL_CFLAGS := $(shell gsl-config --cflags 2>/dev/null)
GSL_LIBS := $(shell gsl-config --libs 2>/dev/null)
ifeq ($(GSL_LIBS),)
    GSL_LIBS := -lgsl -lgslcblas -lm
    $(warning gsl-config not found on PATH; linking with bare -lgsl -lgslcblas -lm, which may not find Homebrew's GSL on macOS)
endif

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

CXXFLAGS := -std=c++11 -O2 $(OMP) $(GSL_CFLAGS)
LDFLAGS := $(OMP)

.PHONY: all clean

all: $(binary)

$(LIB):
	$(MAKE) -C $(TP_STANDALONE_DIR)/libtwopunctures OMP="$(OMP)"

Main.o: Main.cc
	$(CXX) $(CXXFLAGS) $(INC) -c Main.cc -o Main.o

$(binary): Main.o $(LIB)
	$(CXX) $(LDFLAGS) -o $(binary) Main.o $(LIB) $(OMP_LIBS) $(GSL_LIBS)

clean:
	rm -f Main.o $(binary)
