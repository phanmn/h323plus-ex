// h323plus_ex_nif.cpp
// Simplified Elixir NIF wrapper for H323Plus library

#include <erl_nif.h>
#include <string.h>
#include <string>
#include <map>
#include <mutex>

// Declare the wrapper functions without including H323Plus headers
extern "C" {
    const char* h323plus_get_version();
    unsigned h323plus_get_major_version();
    unsigned h323plus_get_minor_version();
    unsigned h323plus_get_build_number();

    void* h323plus_create_endpoint(const char* name);
    void h323plus_destroy_endpoint(void* endpoint);

    void h323plus_set_gatekeeper_password(void* endpoint, const char* password);
    int h323plus_use_gatekeeper(void* endpoint, const char* address, const char* identifier, const char* interface);
    void h323plus_set_gatekeeper_callback(void* endpoint, void (*callback)(const char*, bool, void*), void* user_data);
    int h323plus_is_registered_with_gatekeeper(void* endpoint);
    const char* h323plus_get_gatekeeper_identifier(void* endpoint);

    int h323plus_listen(void* endpoint, int port);
    void h323plus_set_call_callback(void* endpoint, void (*callback)(const char*, const char*, void*), void* user_data);

    int h323plus_make_call(void* endpoint, const char* remote_party, char* token_buffer, int buffer_len);
    int h323plus_accept_call(void* endpoint, const char* token);
    int h323plus_reject_call(void* endpoint, const char* token);
    int h323plus_clear_call(void* endpoint, const char* token);
    void h323plus_set_unix_socket(void* endpoint, const char* socket_path);
}

// Type to store callback information
struct CallbackData {
    ErlNifPid pid;
};

// Global callback lock
static std::mutex g_callback_mutex;
static std::map<void*, CallbackData*> g_callbacks;

// Resource type for endpoint
static ErlNifResourceType* endpoint_resource_type = nullptr;

// Resource wrapper for endpoint
typedef struct {
    void* endpoint;
} EndpointResource;

// Helper for creating error tuples
static ERL_NIF_TERM make_error(ErlNifEnv* env, const char* reason) {
    return enif_make_tuple2(env,
                           enif_make_atom(env, "error"),
                           enif_make_string(env, reason, ERL_NIF_LATIN1));
}

// Helper for creating atoms
static ERL_NIF_TERM make_atom(ErlNifEnv* env, const char* atom_name) {
    ERL_NIF_TERM atom;
    if (!enif_make_existing_atom(env, atom_name, &atom, ERL_NIF_LATIN1)) {
        atom = enif_make_atom(env, atom_name);
    }
    return atom;
}

// Callback function that will be called when a new call comes in
static void on_incoming_call(const char* token, const char* caller_id, void* user_data) {
    void* endpoint = user_data;

    std::lock_guard<std::mutex> lock(g_callback_mutex);
    auto it = g_callbacks.find(endpoint);
    if (it == g_callbacks.end() || !it->second) {
        return;
    }

    CallbackData* data = it->second;

    // Create a new environment for the callback
    ErlNifEnv* env = enif_alloc_env();

    // Create the message: {incoming_call, token, caller_id}
    ERL_NIF_TERM msg = enif_make_tuple3(
        env,
        make_atom(env, "incoming_call"),
        enif_make_string(env, token, ERL_NIF_LATIN1),
        enif_make_string(env, caller_id, ERL_NIF_LATIN1)
    );

    // Send the message to the registered process
    enif_send(NULL, &data->pid, env, msg);

    // Free the environment
    enif_free_env(env);
}

// Callback function for gatekeeper events
static void on_gatekeeper_event(const char* gk_id, bool success, void* user_data) {
    void* endpoint = user_data;

    std::lock_guard<std::mutex> lock(g_callback_mutex);
    auto it = g_callbacks.find(endpoint);
    if (it == g_callbacks.end() || !it->second) {
        return;
    }

    CallbackData* data = it->second;

    // Create a new environment for the callback
    ErlNifEnv* env = enif_alloc_env();

    // Create the message: {gatekeeper_event, success, gk_id}
    ERL_NIF_TERM msg = enif_make_tuple3(
        env,
        make_atom(env, "gatekeeper_event"),
        success ? make_atom(env, "true") : make_atom(env, "false"),
        enif_make_string(env, gk_id, ERL_NIF_LATIN1)
    );

    // Send the message to the registered process
    enif_send(NULL, &data->pid, env, msg);

    // Free the environment
    enif_free_env(env);
}

// NIF function to get Opal version
static ERL_NIF_TERM get_version(ErlNifEnv* env, int argc, const ERL_NIF_TERM argv[]) {
    try {
        const char* version = h323plus_get_version();

        // Convert C string to Erlang binary
        ErlNifBinary bin;
        size_t len = strlen(version);
        enif_alloc_binary(len, &bin);
        memcpy(bin.data, version, len);

        return enif_make_tuple2(env,
                               make_atom(env, "ok"),
                               enif_make_binary(env, &bin));
    } catch (...) {
        return make_error(env, "Unknown error in get_version");
    }
}

// NIF function to get Opal version components
static ERL_NIF_TERM get_version_info(ErlNifEnv* env, int argc, const ERL_NIF_TERM argv[]) {
    try {
        unsigned major = h323plus_get_major_version();
        unsigned minor = h323plus_get_minor_version();
        unsigned build = h323plus_get_build_number();

        return enif_make_tuple2(env,
                               make_atom(env, "ok"),
                               enif_make_tuple3(env,
                                              enif_make_uint(env, major),
                                              enif_make_uint(env, minor),
                                              enif_make_uint(env, build)));
    } catch (...) {
        return make_error(env, "Unknown error in get_version_info");
    }
}

// NIF function to create an endpoint
static ERL_NIF_TERM create_endpoint(ErlNifEnv* env, int argc, const ERL_NIF_TERM argv[]) {
    if (argc < 1) {
        return enif_make_badarg(env);
    }

    // Get name parameter
    char name[256];
    if (!enif_get_string(env, argv[0], name, sizeof(name), ERL_NIF_LATIN1)) {
        return make_error(env, "Invalid name parameter");
    }

    // Create endpoint
    void* endpoint = h323plus_create_endpoint(name);
    if (!endpoint) {
        return make_error(env, "Failed to create H323 endpoint");
    }

    // Setup callbacks
    CallbackData* data = new CallbackData();
    if (!enif_self(env, &data->pid)) {
        delete data;
        return make_error(env, "Failed to get current process ID");
    }

    // Store callback data
    {
        std::lock_guard<std::mutex> lock(g_callback_mutex);
        g_callbacks[endpoint] = data;
    }

    // Setup the callbacks for calls and gatekeeper events
    h323plus_set_call_callback(endpoint, on_incoming_call, endpoint);
    h323plus_set_gatekeeper_callback(endpoint, on_gatekeeper_event, endpoint);

    // Wrap in resource
    EndpointResource* res = (EndpointResource*)enif_alloc_resource(
        endpoint_resource_type, sizeof(EndpointResource));
    res->endpoint = endpoint;

    // Return resource
    ERL_NIF_TERM result = enif_make_resource(env, res);
    enif_release_resource(res);

    return enif_make_tuple2(env, make_atom(env, "ok"), result);
}

// NIF function to set gatekeeper password
static ERL_NIF_TERM set_gatekeeper_password(ErlNifEnv* env, int argc, const ERL_NIF_TERM argv[]) {
    if (argc < 2) {
        return enif_make_badarg(env);
    }

    // Get endpoint resource
    EndpointResource* res;
    if (!enif_get_resource(env, argv[0], endpoint_resource_type, (void**)&res)) {
        return make_error(env, "Invalid endpoint resource");
    }

    if (!res->endpoint) {
        return make_error(env, "Endpoint is null");
    }

    // Get password parameter
    char password[256];
    if (!enif_get_string(env, argv[1], password, sizeof(password), ERL_NIF_LATIN1)) {
        return make_error(env, "Invalid password parameter");
    }

    // Set password
    h323plus_set_gatekeeper_password(res->endpoint, password);

    return make_atom(env, "ok");
}

// NIF function to use gatekeeper
static ERL_NIF_TERM use_gatekeeper(ErlNifEnv* env, int argc, const ERL_NIF_TERM argv[]) {
    if (argc < 4) {
        return enif_make_badarg(env);
    }

    // Get endpoint resource
    EndpointResource* res;
    if (!enif_get_resource(env, argv[0], endpoint_resource_type, (void**)&res)) {
        return make_error(env, "Invalid endpoint resource");
    }

    if (!res->endpoint) {
        return make_error(env, "Endpoint is null");
    }

    // Get parameters
    char address[256] = {0};
    char identifier[256] = {0};
    char interface[256] = {0};

    // Get the optional parameters, empty strings are allowed
    if (enif_is_binary(env, argv[1])) {
        enif_get_string(env, argv[1], address, sizeof(address), ERL_NIF_LATIN1);
    }

    if (enif_is_binary(env, argv[2])) {
        enif_get_string(env, argv[2], identifier, sizeof(identifier), ERL_NIF_LATIN1);
    }

    if (enif_is_binary(env, argv[3])) {
        enif_get_string(env, argv[3], interface, sizeof(interface), ERL_NIF_LATIN1);
    }

    // Use gatekeeper
    if (h323plus_use_gatekeeper(res->endpoint, address, identifier, interface)) {
        return make_atom(env, "ok");
    } else {
        return make_error(env, "Failed to use gatekeeper");
    }
}

// NIF function to check if registered with gatekeeper
static ERL_NIF_TERM is_registered_with_gatekeeper(ErlNifEnv* env, int argc, const ERL_NIF_TERM argv[]) {
    if (argc < 1) {
        return enif_make_badarg(env);
    }

    // Get endpoint resource
    EndpointResource* res;
    if (!enif_get_resource(env, argv[0], endpoint_resource_type, (void**)&res)) {
        return make_error(env, "Invalid endpoint resource");
    }

    if (!res->endpoint) {
        return make_error(env, "Endpoint is null");
    }

    // Check registration
    if (h323plus_is_registered_with_gatekeeper(res->endpoint)) {
        return make_atom(env, "true");
    } else {
        return make_atom(env, "false");
    }
}

// NIF function to get gatekeeper identifier
static ERL_NIF_TERM get_gatekeeper_identifier(ErlNifEnv* env, int argc, const ERL_NIF_TERM argv[]) {
    if (argc < 1) {
        return enif_make_badarg(env);
    }

    // Get endpoint resource
    EndpointResource* res;
    if (!enif_get_resource(env, argv[0], endpoint_resource_type, (void**)&res)) {
        return make_error(env, "Invalid endpoint resource");
    }

    if (!res->endpoint) {
        return make_error(env, "Endpoint is null");
    }

    // Get identifier
    const char* id = h323plus_get_gatekeeper_identifier(res->endpoint);

    // Convert C string to Erlang binary
    ErlNifBinary bin;
    size_t len = strlen(id);
    enif_alloc_binary(len, &bin);
    memcpy(bin.data, id, len);

    return enif_make_tuple2(env,
                          make_atom(env, "ok"),
                          enif_make_binary(env, &bin));
}

// NIF function to register a callback for incoming calls
static ERL_NIF_TERM register_callback(ErlNifEnv* env, int argc, const ERL_NIF_TERM argv[]) {
    if (argc < 1) {
        return enif_make_badarg(env);
    }

    // Get endpoint resource
    EndpointResource* res;
    if (!enif_get_resource(env, argv[0], endpoint_resource_type, (void**)&res)) {
        return make_error(env, "Invalid endpoint resource");
    }

    if (!res->endpoint) {
        return make_error(env, "Endpoint is null");
    }

    // Register callback
    std::lock_guard<std::mutex> lock(g_callback_mutex);

    // Clean up any existing callback data
    auto it = g_callbacks.find(res->endpoint);
    if (it != g_callbacks.end() && it->second) {
        delete it->second;
    }

    // Create new callback data
    CallbackData* data = new CallbackData();
    if (!enif_self(env, &data->pid)) {
        delete data;
        return make_error(env, "Failed to get current process ID");
    }

    // Store callback data
    g_callbacks[res->endpoint] = data;

    // Register callback with H323Plus
    h323plus_set_call_callback(res->endpoint, on_incoming_call, res->endpoint);
    h323plus_set_gatekeeper_callback(res->endpoint, on_gatekeeper_event, res->endpoint);

    return make_atom(env, "ok");
}

// NIF function to start listening for calls
static ERL_NIF_TERM listen_for_calls(ErlNifEnv* env, int argc, const ERL_NIF_TERM argv[]) {
    if (argc < 2) {
        return enif_make_badarg(env);
    }

    // Get endpoint resource
    EndpointResource* res;
    if (!enif_get_resource(env, argv[0], endpoint_resource_type, (void**)&res)) {
        return make_error(env, "Invalid endpoint resource");
    }

    // Get port parameter
    int port;
    if (!enif_get_int(env, argv[1], &port)) {
        return make_error(env, "Port must be an integer");
    }

    // Start listening
    if (!h323plus_listen(res->endpoint, port)) {
        return make_error(env, "Failed to start listener");
    }

    return make_atom(env, "ok");
}

// NIF function to make a call
static ERL_NIF_TERM make_call(ErlNifEnv* env, int argc, const ERL_NIF_TERM argv[]) {
    if (argc < 2) {
        return enif_make_badarg(env);
    }

    // Get endpoint resource
    EndpointResource* res;
    if (!enif_get_resource(env, argv[0], endpoint_resource_type, (void**)&res)) {
        return make_error(env, "Invalid endpoint resource");
    }

    // Get remote party parameter
    char remote_party[512];
    if (!enif_get_string(env, argv[1], remote_party, sizeof(remote_party), ERL_NIF_LATIN1)) {
        return make_error(env, "Invalid remote party parameter");
    }

    // Make the call
    char token[256] = {0};
    if (!h323plus_make_call(res->endpoint, remote_party, token, sizeof(token))) {
        return make_error(env, "Failed to make call");
    }

    // Convert C string to Erlang binary
    ErlNifBinary bin;
    size_t len = strlen(token);
    enif_alloc_binary(len, &bin);
    memcpy(bin.data, token, len);

    return enif_make_tuple2(env,
                          make_atom(env, "ok"),
                          enif_make_binary(env, &bin));
}

// NIF function to accept a call
static ERL_NIF_TERM accept_call(ErlNifEnv* env, int argc, const ERL_NIF_TERM argv[]) {
    if (argc < 2) {
        return enif_make_badarg(env);
    }

    // Get endpoint resource
    EndpointResource* res;
    if (!enif_get_resource(env, argv[0], endpoint_resource_type, (void**)&res)) {
        return make_error(env, "Invalid endpoint resource");
    }

    // Get token parameter
    char token[256];
    if (!enif_get_string(env, argv[1], token, sizeof(token), ERL_NIF_LATIN1)) {
        return make_error(env, "Invalid token parameter");
    }

    // Accept call
    if (!h323plus_accept_call(res->endpoint, token)) {
        return make_error(env, "Failed to accept call");
    }

    return make_atom(env, "ok");
}

// NIF function to reject a call
static ERL_NIF_TERM reject_call(ErlNifEnv* env, int argc, const ERL_NIF_TERM argv[]) {
    if (argc < 2) {
        return enif_make_badarg(env);
    }

    // Get endpoint resource
    EndpointResource* res;
    if (!enif_get_resource(env, argv[0], endpoint_resource_type, (void**)&res)) {
        return make_error(env, "Invalid endpoint resource");
    }

    // Get token parameter
    char token[256];
    if (!enif_get_string(env, argv[1], token, sizeof(token), ERL_NIF_LATIN1)) {
        return make_error(env, "Invalid token parameter");
    }

    // Reject call
    if (!h323plus_reject_call(res->endpoint, token)) {
        return make_error(env, "Failed to reject call");
    }

    return make_atom(env, "ok");
}

// NIF function to clear a call
static ERL_NIF_TERM clear_call(ErlNifEnv* env, int argc, const ERL_NIF_TERM argv[]) {
    if (argc < 2) {
        return enif_make_badarg(env);
    }

    // Get endpoint resource
    EndpointResource* res;
    if (!enif_get_resource(env, argv[0], endpoint_resource_type, (void**)&res)) {
        return make_error(env, "Invalid endpoint resource");
    }

    // Get token parameter
    char token[256];
    if (!enif_get_string(env, argv[1], token, sizeof(token), ERL_NIF_LATIN1)) {
        return make_error(env, "Invalid token parameter");
    }

    // Clear call
    if (!h323plus_clear_call(res->endpoint, token)) {
        return make_error(env, "Failed to clear call");
    }

    return make_atom(env, "ok");
}

#include "erl_nif.h"

// Declare the function to be exposed to Elixir
static ERL_NIF_TERM h323plus_set_unix_socket_nif(ErlNifEnv* env, int argc, const ERL_NIF_TERM argv[]) {
    if (argc != 2) {
        return enif_make_badarg(env);
    }

    // Get the H323 endpoint reference from the NIF argument
    EndpointResource* res;
    if (!enif_get_resource(env, argv[0], endpoint_resource_type, (void**)&res)) {
        return make_error(env, "Invalid endpoint resource");
    }

    char socket_path[256];
    // Get the socket path from the NIF argument
    if (!enif_get_string(env, argv[1], socket_path, sizeof(socket_path), ERL_NIF_LATIN1)) {
        return enif_make_badarg(env);
    }

    // Cast to CallbackH323EndPoint and set the socket
    h323plus_set_unix_socket(res->endpoint, socket_path);

    return enif_make_atom(env, "ok");
}


// Resource cleanup for endpoints
static void endpoint_destructor(ErlNifEnv* env, void* obj) {
    EndpointResource* res = (EndpointResource*)obj;
    if (res && res->endpoint) {
        // Clean up callback data
        {
            std::lock_guard<std::mutex> lock(g_callback_mutex);
            auto it = g_callbacks.find(res->endpoint);
            if (it != g_callbacks.end() && it->second) {
                delete it->second;
                g_callbacks.erase(it);
            }
        }

        // Destroy endpoint
        h323plus_destroy_endpoint(res->endpoint);
        res->endpoint = nullptr;
    }
}

// NIF function declarations
static ErlNifFunc nif_funcs[] = {
    {"get_version", 0, get_version},
    {"get_version_info", 0, get_version_info},
    {"create_endpoint", 1, create_endpoint},
    {"set_gatekeeper_password", 2, set_gatekeeper_password},
    {"use_gatekeeper", 4, use_gatekeeper},
    {"is_registered_with_gatekeeper", 1, is_registered_with_gatekeeper},
    {"get_gatekeeper_identifier", 1, get_gatekeeper_identifier},
    {"register_callback", 1, register_callback},
    {"listen_for_calls", 2, listen_for_calls},
    {"make_call", 2, make_call},
    {"accept_call", 2, accept_call},
    {"reject_call", 2, reject_call},
    {"clear_call", 2, clear_call}
    // // Unix socket functions
    // {"create_unix_socket", 2, nif_create_unix_socket},
    // {"send_unix_data", 3, nif_send_unix_data},
    // {"receive_unix_data", 2, nif_receive_unix_data}
};

// NIF initialization
static int load(ErlNifEnv* env, void** priv_data, ERL_NIF_TERM load_info) {
    // Initialize resource type for endpoint
    endpoint_resource_type =
        enif_open_resource_type(env, NULL, "h323plus_ex_endpoint_resource",
                               endpoint_destructor, ERL_NIF_RT_CREATE, NULL);

    if (!endpoint_resource_type) {
        return -1;
    }

    return 0;
}

// NIF upgrade
static int upgrade(ErlNifEnv* env, void** priv_data, void** old_priv_data, ERL_NIF_TERM load_info) {
    return 0;
}

// NIF unload
static void unload(ErlNifEnv* env, void* priv_data) {
    // Clean up global callback map
    std::lock_guard<std::mutex> lock(g_callback_mutex);
    for (auto& pair : g_callbacks) {
        if (pair.second) {
            delete pair.second;
        }
    }
    g_callbacks.clear();
}

// Module initialization
ERL_NIF_INIT(Elixir.H323PlusEx.Native, nif_funcs, load, NULL, upgrade, unload);