// Parfile-driven driver for twopunctures-standalone. This is NOT part of
// the twopunctures-standalone clone (which is left completely untouched at
// /scratch/sswain/twopunctures-standalone) — it links against that repo's
// pristine, unmodified libtwopunctures.a and headers, and lives here so the
// tuning pipeline can actually vary parameters between iterations. See
// Makefile in this directory.
//
// Format: "key = value" per line (vectors as "x y z" on one line), '#'
// starts a comment. See params.par for the full set of recognized keys.
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <cctype>
#include <fstream>
#include <sstream>
#include <string>
#include "TwoPunctures.h"

namespace {

std::string trim(const std::string &s) {
	size_t a = s.find_first_not_of(" \t\r\n");
	if (a == std::string::npos) return "";
	size_t b = s.find_last_not_of(" \t\r\n");
	return s.substr(a, b - a + 1);
}

bool parse_bool(const std::string &v) {
	std::string s = v;
	for (auto &c : s) c = (char)tolower((unsigned char)c);
	return (s == "true" || s == "1" || s == "yes");
}

void parse_vec3(const std::string &v, double out[3]) {
	std::istringstream iss(v);
	iss >> out[0] >> out[1] >> out[2];
}

// Fields not present in the file keep whatever TP::Parameters' constructor
// (or the pre-parse defaults set in main()) already set them to.
void read_params_file(const char *path, TP::Parameters &tp) {
	std::ifstream in(path);
	if (!in) {
		fprintf(stderr, "ERROR: could not open parameter file '%s'\n", path);
		exit(1);
	}

	std::string line;
	while (std::getline(in, line)) {
		size_t hash = line.find('#');
		if (hash != std::string::npos) line = line.substr(0, hash);
		line = trim(line);
		if (line.empty()) continue;

		size_t eq = line.find('=');
		if (eq == std::string::npos) continue;
		std::string key = trim(line.substr(0, eq));
		std::string val = trim(line.substr(eq + 1));
		if (val.empty()) continue;

		if      (key == "verbose")            tp.verbose = parse_bool(val);
		else if (key == "give_bare_mass")     tp.give_bare_mass = parse_bool(val);
		else if (key == "target_M_plus")      tp.target_M_plus = atof(val.c_str());
		else if (key == "target_M_minus")     tp.target_M_minus = atof(val.c_str());
		else if (key == "par_m_plus")         tp.par_m_plus = atof(val.c_str());
		else if (key == "par_m_minus")        tp.par_m_minus = atof(val.c_str());
		else if (key == "adm_tol")            tp.adm_tol = atof(val.c_str());
		else if (key == "par_b")              tp.par_b = atof(val.c_str());
		else if (key == "par_bv")             tp.par_bv = atof(val.c_str());
		else if (key == "center_offset_x")    tp.center_offset[0] = atof(val.c_str());
		else if (key == "center_offset_y")    tp.center_offset[1] = atof(val.c_str());
		else if (key == "center_offset_z")    tp.center_offset[2] = atof(val.c_str());
		else if (key == "swap_xz")            tp.swap_xz = parse_bool(val);
		else if (key == "par_P_plus")         parse_vec3(val, tp.par_P_plus);
		else if (key == "par_P_minus")        parse_vec3(val, tp.par_P_minus);
		else if (key == "par_S_plus")         parse_vec3(val, tp.par_S_plus);
		else if (key == "par_S_minus")        parse_vec3(val, tp.par_S_minus);
		else if (key == "npoints_A")          tp.npoints_A = atoi(val.c_str());
		else if (key == "npoints_B")          tp.npoints_B = atoi(val.c_str());
		else if (key == "npoints_phi")        tp.npoints_phi = atoi(val.c_str());
		else if (key == "Newton_tol")         tp.Newton_tol = atof(val.c_str());
		else if (key == "Newton_maxit")       tp.Newton_maxit = atoi(val.c_str());
		else if (key == "TP_epsilon")         tp.TP_epsilon = atof(val.c_str());
		else if (key == "TP_Tiny")            tp.TP_Tiny = atof(val.c_str());
		else if (key == "TP_Extend_Radius")   tp.TP_Extend_Radius = atof(val.c_str());
		else if (key == "initial_lapse")      tp.initial_lapse = val;
		else if (key == "initial_lapse_psi_exponent") tp.initial_lapse_psi_exponent = atof(val.c_str());
		else if (key == "use_spectral_interpolation")
			tp.grid_setup_method = parse_bool(val) ? "evaluation" : "Taylor expansion";
		else if (key == "do_residuum_debug_output") tp.do_residuum_debug_output = parse_bool(val);
		else if (key == "do_initial_debug_output")  tp.do_initial_debug_output = parse_bool(val);
		else
			fprintf(stderr, "WARNING: unrecognized parameter '%s' in %s, ignoring\n", key.c_str(), path);
	}
}

} // namespace

int main(int argc, char *argv[]) {

	fprintf(stderr, "##### This is TwoPunctures-Standalone (parfile-driven build) #####\n");

	if (argc < 2) {
		fprintf(stderr, "Usage: %s <parameter file>\n", argv[0]);
		return 1;
	}

	fprintf(stderr, "Reading parameters from %s...\n\n", argv[1]);

	// TP::Parameters' constructor (in the pristine, unmodified library)
	// unconditionally prints its pre-parse defaults, which have nothing to
	// do with what argv[1] actually requests. Rather than let that
	// misleading block reach the log, mute stderr for just this one
	// construction and restore it immediately after; the real, correct
	// values are printed explicitly below once read_params_file() has run.
	fflush(stderr);
	int saved_stderr_fd = dup(fileno(stderr));
	FILE *devnull = fopen("/dev/null", "w");
	dup2(fileno(devnull), fileno(stderr));

	TP::TwoPunctures tp;

	fflush(stderr);
	dup2(saved_stderr_fd, fileno(stderr));
	close(saved_stderr_fd);
	fclose(devnull);

	// smoothen out the infinities at punctures; overridable via TP_epsilon
	// in the parameter file, this is just the pre-parse fallback default.
	tp.TP_epsilon = 1e-6;

	read_params_file(argv[1], tp);

	fprintf(stderr, "TP: Target ADM masses: M_p=%f, M_m=%f\n", tp.target_M_plus, tp.target_M_minus);
	fprintf(stderr, "TP: Momenta: P_plus=(%f,%f,%f)  P_minus=(%f,%f,%f)\n",
		tp.par_P_plus[0], tp.par_P_plus[1], tp.par_P_plus[2],
		tp.par_P_minus[0], tp.par_P_minus[1], tp.par_P_minus[2]);
	fprintf(stderr, "TP: Spins: S_plus=(%f,%f,%f)  S_minus=(%f,%f,%f)\n",
		tp.par_S_plus[0], tp.par_S_plus[1], tp.par_S_plus[2],
		tp.par_S_minus[0], tp.par_S_minus[1], tp.par_S_minus[2]);
	fprintf(stderr, "TP: par_b=%f  center_offset=(%f,%f,%f)\n\n",
		tp.par_b, tp.center_offset[0], tp.center_offset[1], tp.center_offset[2]);

	fprintf(stderr, "Running Preparation code...\n");
	tp.Run();

	return 0;
}
