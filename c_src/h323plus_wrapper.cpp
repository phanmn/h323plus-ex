// h323plus_wrapper.cpp
// Wrapper functions for H323Plus to avoid header inclusion issues

#include <string>
#include <cstring>
#include <mutex>
#include <map>

// Include the H323Plus headers with all necessary dependencies
#include <ptlib.h>
#include <ptlib/pprocess.h>
#include "h323.h"

// Forward declarations
class SimpleH323Process;

// Global state
static bool g_initialized = false;
static std::mutex g_mutex;
static std::map<void*, H323EndPoint*> g_endpoints;
static SimpleH323Process* g_process = NULL;

// Simple extension of PProcess to fulfill the abstract class requirement
class SimpleH323Process : public PProcess {
public:
    SimpleH323Process()
        : PProcess("H323PlusEx", "H323PlusEx", 1, 0, ReleaseCode, 1)
    { }

    void Main() { }  // Required pure virtual function
};

// Custom endpoint class with callback support
class CallbackH323EndPoint : public H323EndPoint {
public:
    CallbackH323EndPoint() : H323EndPoint() {}

    // Function pointer type for call callbacks
    typedef void (*CallCallback)(const char* token, const char* caller_id, void* user_data);
    typedef void (*GatekeeperCallback)(const char* gkid, bool success, void* user_data);

    // Set callback for new calls
    void SetCallCallback(CallCallback callback, void* user_data) {
        m_callCallback = callback;
        m_callUserData = user_data;
    }

    // Set callback for gatekeeper events
    void SetGatekeeperCallback(GatekeeperCallback callback, void* user_data) {
        m_gkCallback = callback;
        m_gkUserData = user_data;
    }

    // Override OnAnswerCall
    virtual H323Connection::AnswerCallResponse OnAnswerCall(
        H323Connection & connection,
        const PString & caller,
        const H323SignalPDU & /*signalPDU*/,
        H323SignalPDU & /*connectPDU*/)
    {
        PString token = connection.GetCallToken();

        if (m_callCallback) {
            m_callCallback(token, caller, m_callUserData);
        }

        // We'll return pending so the Elixir code can decide
        return H323Connection::AnswerCallPending;
    }

    // Gatekeeper status callbacks
    virtual void OnGatekeeperConfirm() {
        H323EndPoint::OnGatekeeperConfirm();

        if (m_gkCallback && gatekeeper != NULL) {
            m_gkCallback(gatekeeper->GetIdentifier(), true, m_gkUserData);
        }
    }

    virtual void OnGatekeeperReject() {
        H323EndPoint::OnGatekeeperReject();

        if (m_gkCallback) {
            m_gkCallback("", false, m_gkUserData);
        }
    }

    virtual void OnRegistrationConfirm(const H323TransportAddress & rasAddress) {
        H323EndPoint::OnRegistrationConfirm(rasAddress);

        if (m_gkCallback && gatekeeper != NULL) {
            m_gkCallback(gatekeeper->GetIdentifier(), true, m_gkUserData);
        }
    }

    virtual void OnRegistrationReject() {
        H323EndPoint::OnRegistrationReject();

        if (m_gkCallback) {
            m_gkCallback("", false, m_gkUserData);
        }
    }

private:
    CallCallback m_callCallback = NULL;
    void* m_callUserData = NULL;
    GatekeeperCallback m_gkCallback = NULL;
    void* m_gkUserData = NULL;
};

// Initialize H323Plus
static bool initialize_h323plus() {
    std::lock_guard<std::mutex> lock(g_mutex);

    if (!g_initialized) {
        // Create a minimal PProcess instance if not already created
        if (g_process == NULL) {
            g_process = new SimpleH323Process();
        }

        // Ensure PProcess::IsInitialised() returns true before using
        if (!PProcess::IsInitialised()) {
            // Wait for process to initialize
            PThread::Sleep(100);
            if (!PProcess::IsInitialised()) {
                return false;
            }
        }

        g_initialized = true;
    }
    return g_initialized;
}

// Wrapper functions that can be called from our NIF
extern "C" {
    const char* h323plus_get_version() {
        initialize_h323plus();

        // Use a static buffer to ensure the string persists
        static char versionBuffer[100];
        const char* version = OpalGetVersion();

        if (version && *version) {
            strncpy(versionBuffer, version, sizeof(versionBuffer) - 1);
            versionBuffer[sizeof(versionBuffer) - 1] = '\0';
        } else {
            // If version is NULL or empty, return the version info as a string
            snprintf(versionBuffer, sizeof(versionBuffer), "%u.%u.%u",
                     OpalGetMajorVersion(), OpalGetMinorVersion(), OpalGetBuildNumber());
        }
        return versionBuffer;
    }

    unsigned h323plus_get_major_version() {
        initialize_h323plus();
        return OpalGetMajorVersion();
    }

    unsigned h323plus_get_minor_version() {
        initialize_h323plus();
        return OpalGetMinorVersion();
    }

    unsigned h323plus_get_build_number() {
        initialize_h323plus();
        return OpalGetBuildNumber();
    }

    // Create an H323 endpoint
    void* h323plus_create_endpoint(const char* name) {
        if (!initialize_h323plus())
            return NULL;

        CallbackH323EndPoint* endpoint = new CallbackH323EndPoint();

        // Convert name to PString
        PString userName(name);
        endpoint->SetLocalUserName(userName);

        // Store in our map
        std::lock_guard<std::mutex> lock(g_mutex);
        g_endpoints[endpoint] = endpoint;

        return endpoint;
    }

    // Destroy an endpoint
    void h323plus_destroy_endpoint(void* endpoint_ptr) {
        if (!endpoint_ptr) return;

        std::lock_guard<std::mutex> lock(g_mutex);
        auto it = g_endpoints.find(endpoint_ptr);
        if (it != g_endpoints.end()) {
            delete it->second;
            g_endpoints.erase(it);
        }
    }

    // Set the gatekeeper password
    void h323plus_set_gatekeeper_password(void* endpoint_ptr, const char* password) {
        if (!endpoint_ptr || !password) return;

        H323EndPoint* endpoint = static_cast<H323EndPoint*>(endpoint_ptr);
        endpoint->SetGatekeeperPassword(password);
    }

    // Register with a gatekeeper
    int h323plus_use_gatekeeper(void* endpoint_ptr, const char* address, const char* identifier, const char* interface) {
        if (!endpoint_ptr) return 0;

        H323EndPoint* endpoint = static_cast<H323EndPoint*>(endpoint_ptr);

        PString addr(address ? address : "");
        PString id(identifier ? identifier : "");
        PString iface(interface ? interface : "");

        return endpoint->UseGatekeeper(addr, id, iface) ? 1 : 0;
    }

    // Set callback for gatekeeper events
    void h323plus_set_gatekeeper_callback(void* endpoint_ptr,
                                         void (*callback)(const char*, bool, void*),
                                         void* user_data)
    {
        if (!endpoint_ptr) return;

        CallbackH323EndPoint* endpoint = static_cast<CallbackH323EndPoint*>(endpoint_ptr);
        endpoint->SetGatekeeperCallback(callback, user_data);
    }

    // Start listening for incoming calls
    int h323plus_listen(void* endpoint_ptr, int port) {
        if (!endpoint_ptr) return 0;

        H323EndPoint* endpoint = static_cast<H323EndPoint*>(endpoint_ptr);

        // Create a listener on specified port
        H323ListenerTCP* listener = new H323ListenerTCP(*endpoint, PIPSocket::Address::GetAny(), port);
        if (endpoint->StartListener(listener)) {
            return 1;
        } else {
            delete listener;
            return 0;
        }
    }

    // Set callback for incoming calls
    void h323plus_set_call_callback(void* endpoint_ptr,
                                    void (*callback)(const char*, const char*, void*),
                                    void* user_data)
    {
        if (!endpoint_ptr) return;

        CallbackH323EndPoint* endpoint = static_cast<CallbackH323EndPoint*>(endpoint_ptr);
        endpoint->SetCallCallback(callback, user_data);
    }

    // Make a call to a remote party
    int h323plus_make_call(void* endpoint_ptr, const char* remote_party, char* token_buffer, int buffer_len) {
        if (!endpoint_ptr || !remote_party || !token_buffer || buffer_len <= 0) return 0;

        H323EndPoint* endpoint = static_cast<H323EndPoint*>(endpoint_ptr);

        PString remoteParty(remote_party);
        PString token;

        if (endpoint->MakeCall(remoteParty, token)) {
            strncpy(token_buffer, token, buffer_len-1);
            token_buffer[buffer_len-1] = '\0';  // Ensure null termination
            return 1;
        }

        return 0;
    }

    // Accept an incoming call
    int h323plus_accept_call(void* endpoint_ptr, const char* token) {
        if (!endpoint_ptr || !token) return 0;

        H323EndPoint* endpoint = static_cast<H323EndPoint*>(endpoint_ptr);

        // Use FindConnectionWithLock but with PString tokens
        PString tokenStr(token);
        H323Connection* connection = endpoint->FindConnectionWithLock(tokenStr);

        if (connection == NULL) {
            return 0;
        }

        connection->AnsweringCall(H323Connection::AnswerCallNow);
        connection->Unlock();
        return 1;
    }

    // Reject an incoming call
    int h323plus_reject_call(void* endpoint_ptr, const char* token) {
        if (!endpoint_ptr || !token) return 0;

        H323EndPoint* endpoint = static_cast<H323EndPoint*>(endpoint_ptr);

        // Use FindConnectionWithLock but with PString tokens
        PString tokenStr(token);
        H323Connection* connection = endpoint->FindConnectionWithLock(tokenStr);

        if (connection == NULL) {
            return 0;
        }

        connection->AnsweringCall(H323Connection::AnswerCallDenied);
        connection->Unlock();
        return 1;
    }

    // Clear a call
    int h323plus_clear_call(void* endpoint_ptr, const char* token) {
        if (!endpoint_ptr || !token) return 0;

        H323EndPoint* endpoint = static_cast<H323EndPoint*>(endpoint_ptr);

        PString tokenStr(token);
        return endpoint->ClearCall(tokenStr) ? 1 : 0;
    }

    // Check if a gatekeeper is registered
    int h323plus_is_registered_with_gatekeeper(void* endpoint_ptr) {
        if (!endpoint_ptr) return 0;

        H323EndPoint* endpoint = static_cast<H323EndPoint*>(endpoint_ptr);
        return endpoint->IsRegisteredWithGatekeeper() ? 1 : 0;
    }

    // Get gatekeeper identifier
    const char* h323plus_get_gatekeeper_identifier(void* endpoint_ptr) {
        if (!endpoint_ptr) return "";

        H323EndPoint* endpoint = static_cast<H323EndPoint*>(endpoint_ptr);
        H323Gatekeeper* gk = endpoint->GetGatekeeper();

        if (gk != NULL) {
            static char idBuffer[100];
            const PString& id = gk->GetIdentifier();
            strncpy(idBuffer, id, sizeof(idBuffer)-1);
            idBuffer[sizeof(idBuffer)-1] = '\0';  // Ensure null termination
            return idBuffer;
        }

        return "";
    }

    // void* h323plus_create_unix_socket(void* endpoint_ptr, const char* socket_path) {
    //     if (!endpoint_ptr || !socket_path) return nullptr;

    //     CallbackH323EndPoint* endpoint = static_cast<CallbackH323EndPoint*>(endpoint_ptr);
    //     return endpoint->create_unix_socket(socket_path);
    // }

    // bool h323plus_send_unix_data(void* endpoint_ptr, void* socket_ptr, const char* data) {
    //     if (!endpoint_ptr || !socket_ptr || !data) return false;

    //     CallbackH323EndPoint* endpoint = static_cast<CallbackH323EndPoint*>(endpoint_ptr);
    //     UnixSocket* socket = static_cast<UnixSocket*>(socket_ptr);

    //     return endpoint->send_unix_data(socket, data);
    // }

    // // Using std::string here to avoid memory leak
    // // When using const, data need to be allocated in the memory to be used after fuction call,
    // // however, there's no way to free the memory in there, so it will cause memory leak.
    // std::string h323plus_receive_unix_data(void* endpoint_ptr, void* socket_ptr) {
    //     if (!endpoint_ptr || !socket_ptr) return "";

    //     CallbackH323EndPoint* endpoint = static_cast<CallbackH323EndPoint*>(endpoint_ptr);
    //     UnixSocket* socket = static_cast<UnixSocket*>(socket_ptr);

    //     return endpoint->receive_unix_data(socket);
    // }
}