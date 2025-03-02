# Makefile for H323Plus Elixir NIF - Two-step compilation approach with OpenSSL

PRIV_DIR = $(MIX_APP_PATH)/priv
NIF_LIB = $(PRIV_DIR)/h323plus_ex_nif.so
WRAPPER_OBJ = $(PRIV_DIR)/h323plus_wrapper.o

# Source files
NIF_SRC = c_src/h323plus_ex_nif.cpp
WRAPPER_SRC = c_src/h323plus_wrapper.cpp

# Directory paths
H323PLUS_DIR = ../h323plus
PTLIB_DIR = ../ptlib

# Find OpenSSL (macOS often has it in /usr/local/opt/openssl or via homebrew)
OPENSSL_DIR = $(shell brew --prefix openssl 2>/dev/null || echo "/usr/local/opt/openssl")

# Compiler flags
CXXFLAGS += -fPIC -O2 -std=c++11 -Wno-deprecated-declarations

# Erlang includes
ERLANG_PATH = $(shell erl -eval 'io:format("~s", [code:root_dir()])' -s init stop -noshell)
ERLANG_INCLUDE = $(ERLANG_PATH)/usr/include

# Include paths for wrapper compilation
WRAPPER_INCLUDES = -I$(ERLANG_INCLUDE) -I$(PTLIB_DIR)/include -I$(H323PLUS_DIR)/include -I$(OPENSSL_DIR)/include

# Includes for NIF compilation (no H323Plus includes)
NIF_INCLUDES = -I$(ERLANG_INCLUDE)

# Library paths and libraries
H323_LIB = $(H323PLUS_DIR)/lib/libh323_Darwin_aarch64__s.a
PTLIB_LIB = $(PTLIB_DIR)/lib_Darwin_aarch64/libpt_s.a

# Additional system libraries (often needed by PTLib)
SYS_LIBS = -L$(OPENSSL_DIR)/lib -lssl -lcrypto -framework CoreFoundation -framework SystemConfiguration -framework CoreAudio -framework AudioToolbox -framework CoreServices

# Main targets
all: $(NIF_LIB)

# Step 1: Compile the wrapper with all H323Plus/PTLib includes
$(WRAPPER_OBJ): $(WRAPPER_SRC)
	@echo "Compiling H323Plus wrapper..."
	@mkdir -p $(PRIV_DIR)
	$(CXX) $(CXXFLAGS) $(WRAPPER_INCLUDES) -c $< -o $@

# Step 2: Compile and link the NIF with the wrapper object
$(NIF_LIB): $(NIF_SRC) $(WRAPPER_OBJ)
	@echo "Building NIF module..."
	$(CXX) $(CXXFLAGS) $(NIF_INCLUDES) -o $@ $^ $(H323_LIB) $(PTLIB_LIB) $(SYS_LIBS) -shared -undefined dynamic_lookup

clean:
	rm -f $(NIF_LIB) $(WRAPPER_OBJ)

# For debugging
print-paths:
	@echo "H323PLUS_DIR: $(H323PLUS_DIR)"
	@echo "PTLIB_DIR: $(PTLIB_DIR)"
	@echo "OPENSSL_DIR: $(OPENSSL_DIR)"
	@echo "ERLANG_INCLUDE: $(ERLANG_INCLUDE)"
	@echo "H323_LIB: $(H323_LIB)"
	@echo "PTLIB_LIB: $(PTLIB_LIB)"
	@ls -la $(H323PLUS_DIR)/lib/obj_s/ 2>/dev/null || echo "H323Plus lib directory not found"
	@ls -la $(PTLIB_DIR)/lib_Darwin_aarch64/ 2>/dev/null || echo "PTLib lib directory not found"
	@ls -la $(OPENSSL_DIR)/lib/ 2>/dev/null || echo "OpenSSL lib directory not found"

print-flags:
	@echo "CXXFLAGS: $(CXXFLAGS)"
	@echo "WRAPPER_INCLUDES: $(WRAPPER_INCLUDES)"
	@echo "NIF_INCLUDES: $(NIF_INCLUDES)"
	@echo "SYS_LIBS: $(SYS_LIBS)"

.PHONY: all clean print-paths print-flags