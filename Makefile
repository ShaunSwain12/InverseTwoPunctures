# Builds ./twopunctures from Main.cc, linked against the pristine,
# unmodified twopunctures-standalone clone's static library and headers.
# Never builds, cleans, or otherwise touches anything under
# TP_STANDALONE_DIR beyond invoking its own Makefile to produce the .a if
# it's missing.

TP_STANDALONE_DIR ?= /scratch/sswain/twopunctures-standalone
LIB := $(TP_STANDALONE_DIR)/libtwopunctures/libtwopunctures.a
INC := -I$(TP_STANDALONE_DIR)/libtwopunctures

CXX := g++
CXXFLAGS := -std=c++11 -O2 -fopenmp
LDFLAGS := -fopenmp
LIBS := -lgsl -lgslcblas -lm

binary := twopunctures

.PHONY: all clean

all: $(binary)

$(LIB):
	$(MAKE) -C $(TP_STANDALONE_DIR)/libtwopunctures

Main.o: Main.cc
	$(CXX) $(CXXFLAGS) $(INC) -c Main.cc -o Main.o

$(binary): Main.o $(LIB)
	$(CXX) $(LDFLAGS) -o $(binary) Main.o $(LIB) $(LIBS)

clean:
	rm -f Main.o $(binary)
