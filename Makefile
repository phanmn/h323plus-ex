# Makefile for H323Plus Elixir NIF - Two-step compilation approach with OpenSSL (Unix/Linux)
MIX_APP_PATH ?= $(shell pwd)
PRIV_DIR = $(MIX_APP_PATH)/priv
NIF_LIB = $(PRIV_DIR)/h323plus_ex_nif.so
WRAPPER_OBJ = $(PRIV_DIR)/h323plus_wrapper.o

# Source files
NIF_SRC = c_src/h323plus_ex_nif.cpp
WRAPPER_SRC = c_src/h323plus_wrapper.cpp

# Directory paths
H323PLUS_DIR = ../h323plus
PTLIB_DIR = ../ptlib

# --- OS Detection ---
OS ?= $(shell uname -s)

ifeq ($(OS), Linux)
    # Find OpenSSL (using pkg-config for more robust detection)
    OPENSSL_CFLAGS = -I/usr/include/openssl/
    OPENSSL_LIBS = $(shell pkg-config --libs openssl 2>/dev/null || echo "-L/usr/local/opt/openssl/lib -lssl -lcrypto")
else
    OPENSSL_DIR = $(shell brew --prefix openssl 2>/dev/null || echo "/usr/local/opt/openssl")
endif

# Compiler flags
CXXFLAGS += -fPIC -frtti -O2 -std=c++11 -Wno-deprecated-declarations

# Erlang includes
ERLANG_PATH = $(shell erl -eval 'io:format("~s", [code:root_dir()])' -s init stop -noshell)
ERLANG_INCLUDE = $(ERLANG_PATH)/usr/include



# Includes for NIF compilation (no H323Plus includes)
NIF_INCLUDES = -I$(ERLANG_INCLUDE)

ifeq ($(OS), Linux)
    # Linux
    # Include paths for wrapper compilation
    WRAPPER_INCLUDES = -I$(ERLANG_INCLUDE) -I$(PTLIB_DIR)/include -I$(H323PLUS_DIR)/include -I/usr/include/openssl

    # ... Library paths and libraries ...
    H323_LIB = $(H323PLUS_DIR)/lib/libh323_linux_x86_64__s.a
    PTLIB_LIB = $(PTLIB_DIR)/lib_linux_x86_64/libpt_s.a

    # Additional system libraries (often needed by PTLib)
    SYS_LIBS = $(OPENSSL_LIBS) -lpthread -lldap -llber -lexpat -lresolv
    LDFLAGS = -shared
else
    # macOS
    # Include paths for wrapper compilation
    WRAPPER_INCLUDES = -I$(ERLANG_INCLUDE) -I$(PTLIB_DIR)/include -I$(H323PLUS_DIR)/include -I$(OPENSSL_DIR)/include

    # Library paths and libraries
    H323_LIB = $(H323PLUS_DIR)/lib/libh323_Darwin_aarch64__s.a
    PTLIB_LIB = $(PTLIB_DIR)/lib_Darwin_aarch64/libpt_s.a

    # Additional system libraries (often needed by PTLib)
    SYS_LIBS = $(OPENSSL_LIBS) -framework CoreFoundation -framework SystemConfiguration -framework CoreAudio -framework AudioToolbox -framework CoreServices
    LDFLAGS = -shared -undefined dynamic_lookup
endif

# Main targets
all: $(NIF_LIB)

# Step 1: Compile the wrapper with all H323Plus/PTLib includes
$(WRAPPER_OBJ): $(WRAPPER_SRC)
	@echo "Compiling H323Plus wrapper..."
	@mkdir -p $(PRIV_DIR)
	$(CXX) $(CXXFLAGS) $(WRAPPER_INCLUDES) -c $< -o $@

$(PRIV_DIR)/unix_socket.o: c_src/unix_socket.cpp c_src/unix_socket.h
	@echo "Compiling Unix Socket Channel..."
	@mkdir -p $(PRIV_DIR)
	$(CXX) $(CXXFLAGS) $(WRAPPER_INCLUDES) -c $< -o $@

# Step 2: Compile and link the NIF with the wrapper object
ifeq ($(OS), Linux)
    NIF_LINK_CMD := $(CXX) $(CXXFLAGS) $(NIF_INCLUDES) -o $@ $^ $(H323_LIB) $(PTLIB_LIB) $(SYS_LIBS) -shared
else    # macOS
    NIF_LINK_CMD := $(CXX) $(CXXFLAGS) $(NIF_INCLUDES) -o $@ $^ $(H323_LIB) $(PTLIB_LIB) $(SYS_LIBS) -shared -undefined dynamic_lookup
endif

$(NIF_LIB): $(NIF_SRC) $(WRAPPER_OBJ) $(PRIV_DIR)/unix_socket.o
	@echo "Building NIF module..."

	$(CXX) $(CXXFLAGS) $(NIF_INCLUDES) -o $@ $(NIF_SRC) $(WRAPPER_OBJ) $(PRIV_DIR)/unix_socket.o $(H323_LIB) $(PTLIB_LIB) $(SYS_LIBS) -shared



clean:
	rm -f $(NIF_LIB) $(WRAPPER_OBJ)

# For debugging
print-paths:
ifeq ($(OS), Linux)
	@echo "H323PLUS_DIR: $(H323PLUS_DIR)"
	@echo "PTLIB_DIR: $(PTLIB_DIR)"
	@echo "SYS_LIBS: $(SYS_LIBS)"
	@echo "OPENSSL_CFLAGS: $(OPENSSL_CFLAGS)"
	@echo "OPENSSL_LIBS: $(OPENSSL_LIBS)"
	@echo "ERLANG_INCLUDE: $(ERLANG_INCLUDE)"
	@echo "H323_LIB: $(H323_LIB)"
	@echo "ERLANG_INCLUDE: $(ERLANG_INCLUDE)"
	@echo "PTLIB_LIB: $(PTLIB_LIB)"
	@ls -la $(H323PLUS_DIR)/lib/obj_s/ 2>/dev/null || echo "H323Plus lib directory not found"
	@ls -la $(PTLIB_DIR)/lib_Darwin_aarch64/ 2>/dev/null || echo "PTLib lib directory not found"
	@ls -la $(OPENSSL_DIR)/lib/ 2>/dev/null || echo "OpenSSL lib directory not found"
else
	@echo "H323PLUS_DIR: $(H323PLUS_DIR)"
	@echo "PTLIB_DIR: $(PTLIB_DIR)"
	@echo "OPENSSL_DIR: $(OPENSSL_DIR)"
	@echo "ERLANG_INCLUDE: $(ERLANG_INCLUDE)"
	@echo "H323_LIB: $(H323_LIB)"
	@echo "PTLIB_LIB: $(PTLIB_LIB)"
	@ls -la $(H323PLUS_DIR)/lib/ 2>/dev/null || echo "H323Plus lib directory not found"
	@ls -la $(PTLIB_DIR)/lib_linux_x86_64/ 2>/dev/null || echo "PTLib lib directory not found" # corrected path
	@pkg-config --libs openssl && echo "OpenSSL lib check (pkg-config): OK" || echo "OpenSSL lib check (pkg-config): FAILED"
endif

print-flags:
	@echo "CXXFLAGS: $(CXXFLAGS)"
	@echo "WRAPPER_INCLUDES: $(WRAPPER_INCLUDES)"
	@echo "NIF_INCLUDES: $(NIF_INCLUDES)"
	@echo "SYS_LIBS: $(SYS_LIBS)"

.PHONY: all clean print-paths print-flags