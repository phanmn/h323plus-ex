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
    
    // Set callback for new calls
    void SetCallCallback(CallCallback callback, void* user_data) {
        m_callback = callback;
        m_userData = user_data;
    }
    
    // Override OnAnswerCall
    virtual H323Connection::AnswerCallResponse OnAnswerCall(
        H323Connection & connection,
        const PString & caller,
        const H323SignalPDU & /*signalPDU*/,
        H323SignalPDU & /*connectPDU*/) 
    {
        PString token = connection.GetCallToken();
        
        if (m_callback) {
            m_callback(token, caller, m_userData);
        }
        
        // We'll return pending so the Elixir code can decide
        return H323Connection::AnswerCallPending;
    }

private:
    CallCallback m_callback = NULL;
    void* m_userData = NULL;
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
}